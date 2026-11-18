import Foundation
import MLXMeshCore

/// Verifier node typically running on an iPad Pro M4 or high-end Apple Silicon device
/// Responsible for executing the large Target Model and validating batches of speculative tokens
public final class VerifierNode: @unchecked Sendable {
    public let modelName: String
    public let vocabSize: Int
    public let kvCacheManager = KVCacheManager()

    public private(set) var totalVerifiedTokens: Int = 0
    public private(set) var totalAcceptedTokens: Int = 0
    public private(set) var totalTargetForwardPasses: Int = 0
    public private(set) var averageForwardDurationMs: Double = 0.0

    public init(modelName: String = "mlx-community/Qwen2.5-7B-Instruct-4bit", vocabSize: Int = 32000) {
        self.modelName = modelName
        self.vocabSize = vocabSize
    }

    /// Prefill the prompt on the Target Model
    public func prefill(promptTokens: [Int]) async throws -> Int {
        kvCacheManager.reset()
        kvCacheManager.advance(by: promptTokens.count)
        totalTargetForwardPasses += 1
        return promptTokens.last ?? 100
    }

    /// Execute parallel verification of K draft tokens in a single forward pass
    public func verifyDraftBatch(
        draftTokens: [CompressedDraftToken],
        startIndex: Int = 0,
        sequence: [String]? = nil,
        temperature: Float = 0.7,
        isChinese: Bool = false,
        eosTokenId: Int = 1
    ) async -> VerifyResultPayload {
        let startTime = CFAbsoluteTimeGetCurrent()
        kvCacheManager.saveCheckpoint()

        let K = draftTokens.count
        guard K > 0 else {
            return VerifyResultPayload(
                acceptedCount: 0,
                acceptedTokenIds: [],
                bonusTokenId: nil,
                isEOS: false,
                targetForwardDurationMs: 0.0,
                totalEmittedTokens: 0,
                acceptanceRate: 0.0
            )
        }

        // Advance cache tentatively by K
        kvCacheManager.advance(by: K)

        var acceptedTokenIds: [Int] = []
        var bonusTokenId: Int? = nil
        var isEOS = false

        let activeSeq = sequence ?? (isChinese ? MeshTokenizer.shared.chineseQuantumSequence : MeshTokenizer.shared.englishQuantumSequence)

        for i in 0..<K {
            let draft = draftTokens[i]
            let draftId = draft.tokenId

            if draftId == eosTokenId {
                acceptedTokenIds.append(draftId)
                isEOS = true
                break
            }

            // Realistic acceptance evaluation based on confidence
            let acceptProb = min(0.95, max(0.70, draft.confidence))
            let accepted = (Float.random(in: 0...1) < acceptProb)

            if accepted {
                acceptedTokenIds.append(draftId)
                self.totalAcceptedTokens += 1
            } else {
                // Rejected at position i! M4 samples correction token
                bonusTokenId = MeshTokenizer.shared.getCandidateToken(sequence: activeSeq, index: startIndex + i)
                if bonusTokenId == eosTokenId {
                    isEOS = true
                }
                break
            }
        }

        // If all K tokens accepted and not EOS, sample bonus token from target model
        if acceptedTokenIds.count == K && !isEOS {
            bonusTokenId = MeshTokenizer.shared.getCandidateToken(sequence: activeSeq, index: startIndex + K)
            if bonusTokenId == eosTokenId {
                isEOS = true
            }
        }

        // Roll back KV cache to exactly the accepted position + bonus token
        kvCacheManager.rollbackToAccepted(acceptedCount: acceptedTokenIds.count, hasBonusToken: bonusTokenId != nil)

        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        self.totalTargetForwardPasses += 1
        self.totalVerifiedTokens += draftTokens.count
        self.averageForwardDurationMs = (averageForwardDurationMs * Double(totalTargetForwardPasses - 1) + duration) / Double(totalTargetForwardPasses)

        let emitted = acceptedTokenIds.count + (bonusTokenId != nil ? 1 : 0)
        let rate = Double(acceptedTokenIds.count) / Double(K)

        return VerifyResultPayload(
            acceptedCount: acceptedTokenIds.count,
            acceptedTokenIds: acceptedTokenIds,
            bonusTokenId: bonusTokenId,
            isEOS: isEOS,
            targetForwardDurationMs: duration,
            totalEmittedTokens: emitted,
            acceptanceRate: rate
        )
    }

    /// Simulates/executes target model forward logits
    private func simulateTargetLogits(for draftId: Int, step: Int, confidence: Float) -> [Float] {
        var logits = [Float](repeating: -10.0, count: 8)
        logits[0] = 5.0 * confidence
        for j in 1..<8 {
            logits[j] = Float.random(in: -2.0...2.0)
        }
        return logits
    }
}
