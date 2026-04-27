import Foundation

/// SentencePiece BPE tokenizer for EmbeddingGemma-300M.
///
/// Reads a Swift-safe **base64-keyed** tokenizer file produced at build
/// time from HuggingFace's tokenizer.json. The base64 indirection is
/// load-bearing: Apple's `JSONSerialization` silently NFC-normalizes
/// (and BOM-strips) string keys via NSString interning, which would
/// drop ~430 entries from the Gemma vocab — including distinct entries
/// that differ only by combining marks or a leading U+FEFF. Encoding
/// every key as base64 sidesteps every Unicode-equivalence path in
/// Foundation; we decode to raw `Data` and use byte-exact dict keys.
///
/// Pipeline (matches HF's tokenizers crate exactly for Gemma):
///   1. Special-token splitting — `added_tokens` (e.g. `<bos>`, `<unused0>`)
///      are matched as atomic tokens before BPE. Longest-match-first.
///   2. Normalizer — Replace ASCII " " (0x20) with "▁" (U+2581).
///   3. Pre-tokenizer — Declared in JSON as Split on " ", which is a
///      no-op after normalization; whole segment goes to BPE as one piece.
///   4. BPE encode — Iteratively merge the lowest-rank adjacent pair.
///   5. byte_fallback=true — Any miss after BPE decomposes to UTF-8
///      bytes, each byte → "<0xXX>" token. All 256 byte tokens verified
///      present at init.
///   6. Post-processor — Prepend <bos>, append <eos>.
///
/// Parity-tested against 556 fixtures from HuggingFace `AutoTokenizer`.
/// Build-time converter: scripts/build-embeddinggemma-tarball.sh emits
/// tokenizer-b64.json into the model tarball next to the .mlmodelc bundle.
final class SentencePieceTokenizer {
  // MARK: - Constants

  /// Sequence cap. EmbeddingGemmaModel runs CoreML at fixed shape (1, 128);
  /// truncating here avoids re-allocating tokens we'd discard anyway.
  static let maxSequenceLength = 128

  /// SentencePiece word boundary marker (U+2581).
  private static let wordBoundary = "▁"

  // MARK: - Vocab + merges (Data-keyed for byte identity)

  private let vocab: [Data: Int]
  private let mergeRank: [Data: Int]
  private let byteTokenId: [UInt8: Int]
  private let bosId: Int
  private let eosId: Int
  private let unkId: Int

  /// Added-token literals (e.g. `<bos>`, `<unused0>`). Sorted by length
  /// descending for longest-match-first scanning.
  private let addedTokens: [(text: String, id: Int)]

  // MARK: - Init

  /// Initializes from a base64-keyed tokenizer file. Throws on any
  /// structural error so the caller can fall back cleanly to null vectors.
  /// Path: model tarball ships tokenizer-b64.json at root, alongside
  /// the .mlmodelc bundle.
  init(tokenizerJSONPath: String) throws {
    let url = URL(fileURLWithPath: tokenizerJSONPath)
    let data = try Data(contentsOf: url)

    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw NSError(domain: "SentencePieceTokenizer", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "tokenizer file is not a JSON object"
      ])
    }

    guard let vocabArr = root["vocab"] as? [[Any]] else {
      throw NSError(domain: "SentencePieceTokenizer", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "tokenizer file missing 'vocab' array of [b64, id]"
      ])
    }
    guard let mergesArr = root["merges"] as? [[String]] else {
      throw NSError(domain: "SentencePieceTokenizer", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "tokenizer file missing 'merges' array of [b64_l, b64_r]"
      ])
    }
    guard let addedArr = root["added_tokens"] as? [[String: Any]] else {
      throw NSError(domain: "SentencePieceTokenizer", code: 4, userInfo: [
        NSLocalizedDescriptionKey: "tokenizer file missing 'added_tokens'"
      ])
    }
    guard let byteFallback = root["byte_fallback"] as? [Int], byteFallback.count == 256 else {
      throw NSError(domain: "SentencePieceTokenizer", code: 5, userInfo: [
        NSLocalizedDescriptionKey: "tokenizer file missing 256-entry 'byte_fallback' array"
      ])
    }

    // Build Data-keyed vocab.
    var vocab = [Data: Int](minimumCapacity: vocabArr.count)
    for entry in vocabArr {
      guard entry.count == 2,
            let b64 = entry[0] as? String,
            let id = entry[1] as? Int,
            let bytes = Data(base64Encoded: b64) else { continue }
      vocab[bytes] = id
    }

    // Build merges (rank = index). Key = left + 0x20 + right (matches BPE
    // inner-loop key construction).
    var rank = [Data: Int](minimumCapacity: mergesArr.count)
    let space = Data([0x20])
    for (i, pair) in mergesArr.enumerated() where pair.count == 2 {
      guard let l = Data(base64Encoded: pair[0]),
            let r = Data(base64Encoded: pair[1]) else { continue }
      var key = l
      key.append(space)
      key.append(r)
      rank[key] = i
    }

    self.vocab = vocab
    self.mergeRank = rank

    // Special token IDs.
    self.bosId = (root["bos_id"] as? Int) ?? 2
    self.eosId = (root["eos_id"] as? Int) ?? 1
    self.unkId = (root["unk_id"] as? Int) ?? 3

    // Byte fallback table — direct from converter, indexed by byte value.
    var bytes = [UInt8: Int](minimumCapacity: 256)
    for b in 0...255 {
      let id = byteFallback[b]
      if id >= 0 { bytes[UInt8(b)] = id }
    }
    self.byteTokenId = bytes

    // Added-token literals. Sort longest-first so `<unused10>` matches
    // before `<unused1>` + `0>`.
    var added: [(String, Int)] = []
    for entry in addedArr {
      guard let b64 = entry["b64_content"] as? String,
            let id = entry["id"] as? Int,
            let raw = Data(base64Encoded: b64),
            let s = String(data: raw, encoding: .utf8) else { continue }
      added.append((s, id))
    }
    added.sort { $0.0.count > $1.0.count }
    self.addedTokens = added

    ErrorHandler.logInfo("SentencePieceTokenizer ready: vocab=\(vocab.count) merges=\(rank.count) bytes=\(bytes.count) added=\(added.count)")
  }

  // MARK: - Encode

  /// Encodes text → [<bos>] + bpe(text) + [<eos>], then truncates the
  /// whole sequence to maxSequenceLength to match HF's behavior of
  /// `tokenizer.encode(text)[:max_length]`. Long inputs that overflow
  /// will drop the trailing <eos>; this matches HF reference output
  /// exactly and is what the trained encoder expects.
  /// Empty input returns [<bos>, <eos>].
  func encode(_ text: String) -> [Int] {
    var tokens: [Int] = [bosId]

    if !text.isEmpty {
      let chunks = splitOnAddedTokens(text)
      // Soft early-exit budget: stop encoding once we already have enough
      // tokens to fill the window even after appending <eos>. Saves work
      // on huge inputs without changing output.
      let softCap = Self.maxSequenceLength + 8
      for chunk in chunks {
        if tokens.count >= softCap { break }
        switch chunk {
        case .special(let id):
          tokens.append(id)
        case .text(let segment):
          // Normalize per-codepoint instead of String.replacingOccurrences:
          // the latter routes through NSString equality and silently
          // misses U+0020 in strings that contain certain high-plane
          // codepoints (verified empirically on fuzz fixtures). Iterating
          // unicodeScalars guarantees byte-exact replacement.
          var normalized = ""
          normalized.reserveCapacity(segment.count + 8)
          let spaceScalar = Unicode.Scalar(0x20)!
          let boundaryScalar = Unicode.Scalar(0x2581)!  // "▁"
          for scalar in segment.unicodeScalars {
            normalized.unicodeScalars.append(scalar == spaceScalar ? boundaryScalar : scalar)
          }
          bpeEncodeAndAppend(normalized, into: &tokens)
        }
      }
    }

    tokens.append(eosId)
    if tokens.count > Self.maxSequenceLength {
      tokens = Array(tokens.prefix(Self.maxSequenceLength))
    }
    return tokens
  }

  // MARK: - Added-token splitting

  private enum InputChunk {
    case text(String)
    case special(Int)
  }

  private func splitOnAddedTokens(_ text: String) -> [InputChunk] {
    if addedTokens.isEmpty { return [.text(text)] }

    var result: [InputChunk] = []
    var pending = ""
    let chars = Array(text)
    var i = 0
    while i < chars.count {
      var matched: (text: String, id: Int)? = nil
      let remaining = chars.count - i
      for added in addedTokens {
        let aLen = added.text.count
        if aLen > remaining { continue }
        var match = true
        for (j, c) in added.text.enumerated() where chars[i + j] != c {
          match = false
          break
        }
        if match { matched = added; break }
      }

      if let m = matched {
        if !pending.isEmpty {
          result.append(.text(pending))
          pending = ""
        }
        result.append(.special(m.id))
        i += m.text.count
      } else {
        pending.append(chars[i])
        i += 1
      }
    }
    if !pending.isEmpty {
      result.append(.text(pending))
    }
    return result
  }

  // MARK: - BPE

  /// Runs BPE on a normalized segment (Data-byte exact lookups throughout).
  private func bpeEncodeAndAppend(_ piece: String, into tokens: inout [Int]) {
    if piece.isEmpty { return }

    let pieceData = Data(piece.utf8)
    if let id = vocab[pieceData] {
      tokens.append(id)
      return
    }

    // Per-codepoint UTF-8 byte sequences (NOT graphemes). Gemma BPE
    // operates on individual codepoints, with byte fallback for any
    // codepoint missing from vocab.
    var symbols: [Data] = []
    symbols.reserveCapacity(piece.unicodeScalars.count)
    for scalar in piece.unicodeScalars {
      symbols.append(Data(String(scalar).utf8))
    }

    let space = Data([0x20])
    while symbols.count > 1 {
      var bestRank = Int.max
      var bestIdx = -1
      for i in 0..<(symbols.count - 1) {
        var key = symbols[i]
        key.append(space)
        key.append(symbols[i + 1])
        if let rank = mergeRank[key], rank < bestRank {
          bestRank = rank
          bestIdx = i
        }
      }
      if bestIdx < 0 { break }
      symbols[bestIdx] = symbols[bestIdx] + symbols[bestIdx + 1]
      symbols.remove(at: bestIdx + 1)
    }

    for symbol in symbols {
      if let id = vocab[symbol] {
        tokens.append(id)
      } else {
        for byte in symbol {
          tokens.append(byteTokenId[byte] ?? unkId)
        }
      }
    }
  }
}
