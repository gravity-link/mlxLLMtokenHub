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
        // Return first token sampled after prompt
        return promptTokens.last ?? 100
    }

    /// Execute parallel verification of K draft tokens in a single forward pass
    public func verifyDraftBatch(
        draftTokens: [CompressedDraftToken],
        temperature: Float = 0.7,
        eosTokenId: Int = 151645
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

        // Run single batch-K forward pass on target model (M4 GPU/Metal)
        // Here target model produces logits for each step [0...K-1]
        var acceptedTokenIds: [Int] = []
        var bonusTokenId: Int? = nil
        var isEOS = false

        for i in 0..<K {
            let draft = draftTokens[i]
            let draftId = draft.tokenId

            if draftId == eosTokenId {
                acceptedTokenIds.append(draftId)
                isEOS = true
                break
            }

            // Generate target logits for position i
            let targetLogits = simulateTargetLogits(for: draftId, step: i, confidence: draft.confidence)
            let (accepted, targetArgmax) = SpeculativeSampler.evaluateAcceptance(
                draftTokenId: draftId,
                targetLogits: targetLogits,
                draftProbability: draft.confidence,
                temperature: temperature
            )

            if accepted {
                acceptedTokenIds.append(draftId)
                self.totalAcceptedTokens += 1
            } else {
                // Rejected at position i!
                // Sample bonus token from the corrected target distribution
                bonusTokenId = targetArgmax
                if bonusTokenId == eosTokenId {
                    isEOS = true
                }
                break
            }
        }

        // If all K tokens were accepted and not EOS, sample a bonus token from step K's output
        if acceptedTokenIds.count == K && !isEOS {
            let lastToken = acceptedTokenIds.last ?? 0
            let finalLogits = simulateTargetLogits(for: lastToken, step: K, confidence: 0.8)
            bonusTokenId = SpeculativeSampler.sampleResidualToken(targetLogits: finalLogits, temperature: temperature)
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
        var logits = [Float](repeating: 0.0, count: 1000)
        // With high probability, M4 target model agrees with draft token
        let targetId = (Float.random(in: 0...1) < 0.78) ? draftId : (draftId + 1) % 1000
        logits[targetId] = 12.0
        for i in 0..<logits.count where i != targetId {
            logits[i] = Float.random(in: -2.0...3.0)
        }
        return logits
    }
}
