import XCTest

class SentencePieceTokenizerTests: XCTestCase {
  var tokenizer: SentencePieceTokenizer?
  var fixtures: [[String: Any]]?

  override func setUp() async throws {
    super.setUp()

    // Load tokenizer from bundled model
    // For testing, we'll initialize with a path (may not exist yet during fixture generation)
    let bundlePath = Bundle(for: type(of: self)).path(forResource: "tokenizer", ofType: "model")
    if let bundlePath = bundlePath {
      do {
        self.tokenizer = try SentencePieceTokenizer(modelPath: bundlePath)
      } catch {
        // Tokenizer not available; tests will be skipped
        self.tokenizer = nil
      }
    }

    // Load fixture file
    if let fixtureURL = Bundle(for: type(of: self)).url(forResource: "sentencepiece-fixtures", withExtension: "json"),
       let data = try? Data(contentsOf: fixtureURL),
       let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
      self.fixtures = json
    }
  }

  /// Test tokenizer parity against all fixture inputs.
  /// Requires fixtures to be populated with real token IDs from HF transformers.
  func testTokenizerParityAllFixtures() throws {
    guard let tokenizer = tokenizer else {
      XCTSkip("Tokenizer not initialized (bundled model not found)")
    }

    guard let fixtures = fixtures else {
      XCTSkip("Fixtures not loaded (sentencepiece-fixtures.json not found)")
    }

    // Check for pending flag (fixtures generated but not yet populated with real tokens)
    if let first = fixtures.first as? [String: Any], first["_pending_real_tokens"] != nil {
      XCTSkip("Fixtures pending real token generation (run: python3 client/macOS/scripts/generate-tokenizer-fixtures.py)")
    }

    var passCount = 0
    var failCount = 0

    for (index, fixture) in fixtures.enumerated() {
      guard let text = fixture["text"] as? String,
            let expectedIds = fixture["expected_token_ids"] as? [Int],
            let description = fixture["description"] as? String else {
        continue
      }

      let actualIds = tokenizer.encode(text)

      if actualIds == expectedIds {
        passCount += 1
      } else {
        failCount += 1
        XCTFail("Fixture [\(index)] \(description): token mismatch\n  Text: \(text)\n  Expected: \(expectedIds.prefix(20))...\n  Actual: \(actualIds.prefix(20))...")
      }
    }

    XCTAssertEqual(failCount, 0, "Tokenizer parity failed on \(failCount)/\(fixtures.count) fixtures")
    print("✓ Tokenizer parity: \(passCount)/\(fixtures.count) fixtures passed")
  }

  /// Test edge cases for tokenizer robustness.
  func testTokenizerEdgeCases() throws {
    guard let tokenizer = tokenizer else {
      XCTSkip("Tokenizer not initialized")
    }

    // Empty string should return BOS token only
    let emptyTokens = tokenizer.encode("")
    XCTAssert(!emptyTokens.isEmpty, "Empty string should return at least BOS token")

    // First token should be BOS (token ID 2 for SentencePiece)
    let firstTokens = tokenizer.encode("hello")
    XCTAssertEqual(firstTokens.first, 2, "First token should be BOS (ID 2)")

    // Very long input should cap at reasonable length
    let longInput = String(repeating: "x", count: 10000)
    let longTokens = tokenizer.encode(longInput)
    XCTAssert(longTokens.count <= 2048, "Tokenizer should cap output at ~2048 tokens")

    // Emoji handling
    let emojiTokens = tokenizer.encode("🚀")
    XCTAssert(!emojiTokens.isEmpty, "Emoji should tokenize successfully")

    // Unicode handling
    let unicodeTokens = tokenizer.encode("Hello 世界 Привет")
    XCTAssert(!unicodeTokens.isEmpty, "Unicode should tokenize successfully")

    print("✓ Edge case tests passed")
  }
}
