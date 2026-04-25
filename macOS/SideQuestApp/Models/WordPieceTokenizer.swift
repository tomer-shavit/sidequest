import Foundation
import CryptoKit

/// BERT WordPiece tokenizer for MiniLM L6 v2 embeddings.
/// Converts raw text to fixed-length token sequences for neural network inference.
/// Validates bundled vocabulary file via SHA256 hash at initialization.
class WordPieceTokenizer {
  private let vocabDict: [String: Int]
  private let unkToken = "[UNK]"
  private let clsToken = "[CLS]"
  private let sepToken = "[SEP]"
  private let padToken = "[PAD]"
  private let maxTokens = 128

  // Token IDs — looked up from vocab at init. Hardcoding fails on real BERT
  // vocab where [CLS]=101 (vocab line 1 is [unused0], not [CLS]). Synthetic
  // unit-test vocabs may place these at other indices, so dynamic lookup
  // keeps both real and test paths correct.
  private var clsId: Int = 101
  private var sepId: Int = 102
  private var padId: Int = 0
  private var unkId: Int = 100

  /// Initializes tokenizer from a vocabulary file.
  /// - Parameters:
  ///   - bundleVocabPath: Path to vocab.txt
  ///   - expectedSHA256: SHA256 of vocab.txt for integrity validation. Pass nil
  ///     to skip validation — used when the source has already been verified
  ///     upstream (e.g. vocab arrived inside a tarball whose tarball-level
  ///     SHA256 was checked in EmbeddingModel.fetchFromS3).
  /// - Throws: NSError if vocab file cannot be read, or if a non-nil
  ///   expectedSHA256 mismatches.
  init(bundleVocabPath: String, expectedSHA256: String? = nil) throws {
    // Read vocab file
    let vocabContent = try String(contentsOfFile: bundleVocabPath, encoding: .utf8)

    if let expectedSHA256 = expectedSHA256 {
      let data = vocabContent.data(using: .utf8) ?? Data()
      let digest = SHA256.hash(data: data)
      let computedHash = digest.map { String(format: "%02x", $0) }.joined()

      guard computedHash == expectedSHA256 else {
        ErrorHandler.logInfo("Vocab SHA256 mismatch: expected \(expectedSHA256), got \(computedHash)")
        throw NSError(domain: "WordPieceTokenizer", code: 1, userInfo: [
          NSLocalizedDescriptionKey: "Vocabulary SHA256 validation failed"
        ])
      }
    }

    // Parse vocab.txt: one word per line, index = line number
    var vocab = [String: Int]()
    var lineNumber = 0
    for line in vocabContent.split(separator: "\n", omittingEmptySubsequences: false) {
      let word = String(line).trimmingCharacters(in: .whitespaces)
      if !word.isEmpty {
        vocab[word] = lineNumber
      }
      lineNumber += 1
    }

    self.vocabDict = vocab

    // Resolve special-token IDs from the vocab. Real BERT vocab has
    // [CLS]=101, [SEP]=102, [UNK]=100, [PAD]=0; synthetic test vocabs may
    // place them elsewhere. Falling back to the hardcoded defaults keeps
    // older fixtures working while real-vocab parity stays correct.
    if let id = vocab[clsToken] { self.clsId = id }
    if let id = vocab[sepToken] { self.sepId = id }
    if let id = vocab[padToken] { self.padId = id }
    if let id = vocab[unkToken] { self.unkId = id }

    ErrorHandler.logInfo("WordPieceTokenizer initialized: \(vocab.count) tokens (cls=\(clsId), sep=\(sepId), unk=\(unkId), pad=\(padId))")
  }

  /// Tokenizes text into fixed-length token sequence.
  /// - Parameters:
  ///   - text: Raw text to tokenize (e.g., user message or assistant response)
  ///   - maxLen: Maximum token sequence length (default 128 for MiniLM)
  /// - Returns: Tuple of (tokenIds: fixed-length array, unkCount: number of [UNK] tokens)
  func tokenize(_ text: String, maxLen: Int = 128) -> (tokenIds: [Int], unkCount: Int) {
    var tokens: [Int] = []
    var unkCount = 0

    // Start with [CLS]
    tokens.append(clsId)

    // BERT BasicTokenizer pipeline: lowercase → whitespace-split → split each
    // whitespace token on punctuation. Without the punctuation step, "hello,"
    // is looked up as one wordpiece (not "hello" + ","), which falls through
    // to [UNK] and breaks parity with the reference HuggingFace tokenizer.
    let words = basicTokenize(text)

    for word in words {
      if tokens.count >= maxLen - 1 { break }  // Reserve one for [SEP]

      var pos = 0
      while pos < word.count {
        var end = word.count
        var found = false

        // Greedy longest-match: try to match from pos to end
        while end > pos {
          let wordStart = word.index(word.startIndex, offsetBy: pos)
          let wordEnd = word.index(word.startIndex, offsetBy: end)
          let subword = String(word[wordStart..<wordEnd])

          // Add ## prefix for subwords (not initial)
          let lookup = pos == 0 ? subword : "##" + subword

          if let tokenId = vocabDict[lookup] {
            tokens.append(tokenId)
            found = true
            pos = end
            break
          }

          end -= 1
        }

        if !found {
          // No match: emit [UNK]
          tokens.append(unkId)
          unkCount += 1
          pos += 1
        }
      }
    }

    // Add [SEP] (but don't exceed maxLen)
    if tokens.count < maxLen {
      tokens.append(sepId)
    }

    // Pad to maxLen with [PAD]
    while tokens.count < maxLen {
      tokens.append(padId)
    }

    // Truncate if needed (shouldn't happen with loop above, but defensive)
    tokens = Array(tokens.prefix(maxLen))

    return (tokenIds: tokens, unkCount: unkCount)
  }

  /// BERT BasicTokenizer port: lowercase + Unicode-whitespace split + per-token
  /// punctuation split. Matches HuggingFace `BertTokenizer(do_lower_case=True)`
  /// pre-WordPiece pipeline closely enough for English developer text.
  /// Accent-stripping + CJK char splitting are intentionally skipped — they
  /// don't fire on the inputs this app handles.
  private func basicTokenize(_ text: String) -> [String] {
    let lowered = text.lowercased()
    var result: [String] = []
    var currentWhitespaceToken = ""

    func flushWordWithPunctSplit() {
      if currentWhitespaceToken.isEmpty { return }
      var current = ""
      for ch in currentWhitespaceToken {
        if isPunctuation(ch) {
          if !current.isEmpty {
            result.append(current)
            current = ""
          }
          result.append(String(ch))
        } else {
          current.append(ch)
        }
      }
      if !current.isEmpty {
        result.append(current)
      }
      currentWhitespaceToken = ""
    }

    for ch in lowered {
      if ch.isWhitespace {
        flushWordWithPunctSplit()
      } else {
        currentWhitespaceToken.append(ch)
      }
    }
    flushWordWithPunctSplit()

    return result
  }

  /// Matches BERT's `_is_punctuation`: ASCII non-alphanumeric punctuation
  /// (codepoints 33-47, 58-64, 91-96, 123-126) ∪ Unicode `P*` category.
  /// Swift's `Character.isPunctuation` covers Unicode P; the explicit ASCII
  /// ranges add chars like `^`, `_`, `` ` ``, `~` that fall outside P but
  /// BERT still treats as punctuation.
  private func isPunctuation(_ char: Character) -> Bool {
    guard let scalar = char.unicodeScalars.first else { return false }
    let cp = scalar.value
    if (cp >= 33 && cp <= 47) || (cp >= 58 && cp <= 64) ||
       (cp >= 91 && cp <= 96) || (cp >= 123 && cp <= 126) {
      return true
    }
    return char.isPunctuation
  }

  /// Computes [UNK] token rate for a token sequence.
  /// - Parameter tokenIds: Token IDs from tokenize()
  /// - Returns: Proportion of [UNK] tokens (0.0 to 1.0)
  func unkRate(tokenIds: [Int]) -> Double {
    guard !tokenIds.isEmpty else { return 0.0 }
    let unkTokenCount = tokenIds.filter { $0 == unkId }.count
    // Exclude [CLS] and [SEP] from denominator (structural tokens)
    let contentTokens = max(1, tokenIds.count - 2)
    return Double(unkTokenCount) / Double(contentTokens)
  }
}
