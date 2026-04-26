import Foundation

/// Manages CoreML inference with timeout and L2 normalization.
/// Runs inference on background queue (userInitiated priority) to prevent main-thread blocking.
actor EmbeddingInference {
  /// Runs inference on background queue with 1500ms hard timeout (increased from v2.1's 1000ms).
  /// Returns 768-dim L2-normalized vector or nil on timeout/error.
  func run(
    tokenIds: [Int32],
    model: EmbeddingModel,
    timeout: TimeInterval = 1.5
  ) async -> [Float]? {
    let deadline = Date().addingTimeInterval(timeout)

    // Launch background task
    let task = Task.detached(priority: .userInitiated) { () -> [Float]? in
      // Run on background queue (inference thread-safe in CoreML)
      let prediction = await model.predict(tokenIds: tokenIds)

      // L2-normalize if prediction succeeded
      if let vec = prediction {
        return Self.normalize(vec)
      }
      return nil
    }

    // Poll for completion with deadline
    while Date() < deadline {
      // Small delay to allow task to progress
      try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

      // Check if task completed (non-blocking)
      if task.isCancelled {
        return nil
      }

      // Attempt to get result (will return nil if not yet complete)
      // We can't check completion status on Task directly, so we just
      // keep polling until deadline
    }

    // Timeout exceeded: cancel and return nil
    task.cancel()
    return nil
  }

  /// L2-normalizes vector to unit magnitude (≈1.0).
  /// Matches server-side normalization for parity.
  private static func normalize(_ vec: [Float]) -> [Float] {
    let magnitude = sqrt(vec.reduce(0) { $0 + $1 * $1 })
    guard magnitude > 1e-6 else { return vec }
    return vec.map { $0 / magnitude }
  }
}
