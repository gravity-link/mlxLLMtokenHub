import Foundation

/// Manages KV cache state and speculative rollbacks
public final class KVCacheManager: @unchecked Sendable {
    public private(set) var currentLength: Int = 0
    private var checkpointLength: Int = 0

    public init() {}

    /// Save current KV cache position before speculative draft forward pass
    public func saveCheckpoint() {
        self.checkpointLength = currentLength
    }

    /// Advance cache position by N tokens
    public func advance(by count: Int) {
        self.currentLength += count
    }

    /// Roll back KV cache to accepted token count
    /// E.g., if K=4 draft tokens were added, but only 2 were accepted,
    /// we roll back currentLength from checkpoint + 4 to checkpoint + 2 (+ 1 bonus)
    public func rollbackToAccepted(acceptedCount: Int, hasBonusToken: Bool = true) {
        self.currentLength = checkpointLength + acceptedCount + (hasBonusToken ? 1 : 0)
    }

    /// Reset cache to zero (for new prompt)
    public func reset() {
        self.currentLength = 0
        self.checkpointLength = 0
    }
}
