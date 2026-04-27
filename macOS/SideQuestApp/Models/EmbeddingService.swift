import Foundation

/// Tokenizer abstraction so EmbeddingService can host either WordPiece (MiniLM)
/// or SentencePiece (EmbeddingGemma) without compile-time coupling to the dim.
protocol EmbeddingTokenizer {
  /// Returns (tokenIds, unkCount). unkCount used to gate inference at >50% UNK.
  func tokenizeForEmbedding(_ text: String) -> ([Int], Int)
}

extension WordPieceTokenizer: EmbeddingTokenizer {
  func tokenizeForEmbedding(_ text: String) -> ([Int], Int) {
    return tokenize(text)
  }
}

extension SentencePieceTokenizer: EmbeddingTokenizer {
  func tokenizeForEmbedding(_ text: String) -> ([Int], Int) {
    let ids = encode(text)
    // Gemma SP rarely emits <unk> on natural text; treat unkCount=0 for now.
    // If swift-transformers exposes an unk-id we can refine. Empty input → 0 tokens.
    return (ids, 0)
  }
}

/// Inference backend abstraction so we can drive either EmbeddingModel (384)
/// or EmbeddingGemmaModel (768) through one EmbeddingService.
protocol EmbeddingBackend {
  /// Returns vector of model-native dim (384 or 768) or nil on failure.
  /// Implementations must enforce their own timeout (~1s budget).
  func embed(tokenIds: [Int]) async -> [Float]?
}

/// Orchestrates full embedding pipeline: tokenization → inference → serialization.
/// Dim-agnostic: returns whatever the backend produces (384 MiniLM, 768 Gemma).
/// Handles graceful degradation for all failure modes (UNK rate, timeout, model error).
actor EmbeddingService {
  private let tokenizer: EmbeddingTokenizer
  private let backend: EmbeddingBackend

  init(tokenizer: EmbeddingTokenizer, backend: EmbeddingBackend) {
    self.tokenizer = tokenizer
    self.backend = backend
  }

  /// Embeds text into L2-normalized vector at backend's native dim (384 or 768).
  /// Returns nil on tokenization failure (>50% UNK), timeout, or model error.
  func embedText(_ text: String) async -> [Float]? {
    let (tokenIds, unkCount) = tokenizer.tokenizeForEmbedding(text)
    let unkRate = tokenIds.count > 0 ? Double(unkCount) / Double(tokenIds.count) : 0

    if unkRate > 0.5 {
      ErrorHandler.logInfo("High [UNK] rate (\(String(format: "%.1f", unkRate * 100))%); input unrecognizable; returning null vector")
      return nil
    }

    if unkCount > 0 {
      ErrorHandler.logInfo("Tokenization: [UNK] rate \(String(format: "%.1f", unkRate * 100))% for input")
    }

    return await backend.embed(tokenIds: tokenIds)
  }

  /// Serializes vector to JSON-safe string array at 6-decimal precision.
  nonisolated func serializeVector(_ vector: [Float]) -> [String] {
    return vector.map { String(format: "%.6f", $0) }
  }

  /// Deserializes string array back to float vector. Accepts 384 or 768 dim.
  nonisolated func deserializeVector(_ strings: [String]) -> [Float]? {
    guard strings.count == 384 || strings.count == 768 else {
      return nil
    }

    var vector = [Float]()
    vector.reserveCapacity(strings.count)
    for str in strings {
      guard let value = Float(str) else {
        return nil
      }
      vector.append(value)
    }
    return vector
  }

  /// Validates vector for finite values (no NaN/Inf) and a known embedding dim.
  nonisolated func isValidVector(_ vector: [Float]?) -> Bool {
    guard let v = vector, v.count == 384 || v.count == 768 else {
      return false
    }
    return v.allSatisfy { !$0.isNaN && !$0.isInfinite }
  }
}

/// Backend wrapping the legacy MiniLM EmbeddingModel + EmbeddingInference (384-dim).
struct MiniLMBackend: EmbeddingBackend {
  let model: EmbeddingModel
  let inference: EmbeddingInference

  func embed(tokenIds: [Int]) async -> [Float]? {
    let tokenIds32 = tokenIds.map { Int32($0) }
    return await inference.run(tokenIds: tokenIds32, model: model, timeout: 1000)
  }
}

/// Backend wrapping EmbeddingGemmaModel (768-dim, native attention_mask path).
struct GemmaBackend: EmbeddingBackend {
  let model: EmbeddingGemmaModel

  func embed(tokenIds: [Int]) async -> [Float]? {
    // Run inference on the actor; enforce 1s wall-clock budget at the call site.
    return await withTaskGroup(of: [Float]?.self) { group in
      group.addTask {
        do {
          return try await model.inference(tokenIds: tokenIds)
        } catch {
          ErrorHandler.logInfo("GemmaBackend inference error: \(error)")
          return nil
        }
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first ?? nil
    }
  }
}
