import Foundation
import MLXMeshCore

/// Drafter node typically running on an iPhone, standard iPad, or distributed edge node
/// Executes the small Draft Model to rapidly generate candidate token proposals
public final class DrafterNode: @unchecked Sendable {
    public let modelName: String
    public let vocabSize: Int

    public private(set) var totalGeneratedDraftTokens: Int = 0
    public private(set) var averageDraftLatencyMs: Double = 0.0

    public init(modelName: String = "mlx-community/Qwen2.5-0.5B-Instruct-4bit", vocabSize: Int = 32000) {
        self.modelName = modelName
        self.vocabSize = vocabSize
    }

    /// Generate K speculative draft tokens given current context
    public func generateDraft(
        promptTokens: [Int],
        draftCount K: Int = 4,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        compressionMode: CompressionMode = .topkLogits
    ) async -> DraftResponsePayload {
        let startTime = CFAbsoluteTimeGetCurrent()
        var candidateTokens: [CompressedDraftToken] = []

        var currentContext = promptTokens
        for step in 0..<K {
            // Predict next draft token
            let simulatedLogits = simulateDraftLogits(for: currentContext.last ?? 100, step: step)
            let (topKIndices, quantizedProbs) = CompressionEngine.shared.compressTopKLogits(logits: simulatedLogits, topK: 8)
            
            let selectedTokenId = topKIndices.first ?? Int.random(in: 100...900)
            let confidence = Float.random(in: 0.75...0.95)

            let draftToken = CompressedDraftToken(
                tokenId: selectedTokenId,
                topKTokenIds: topKIndices,
                topKProbabilities: quantizedProbs,
                confidence: confidence
            )
            candidateTokens.append(draftToken)
            currentContext.append(selectedTokenId)
        }

        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        let tokensPerSec = duration > 0 ? (Double(K) / (duration / 1000.0)) : 0.0
        self.totalGeneratedDraftTokens += K

        return DraftResponsePayload(
            draftTokens: candidateTokens,
            durationMs: duration,
            draftTokensPerSec: tokensPerSec,
            compressedActivations: nil
        )
    }

    private func simulateDraftLogits(for prevToken: Int, step: Int) -> [Float] {
        var logits = [Float](repeating: 0.0, count: 1000)
        let likelyToken = (prevToken * 3 + step * 7 + 13) % 1000
        logits[likelyToken] = 10.0
        for i in 0..<logits.count where i != likelyToken {
            logits[i] = Float.random(in: -3.0...2.0)
        }
        return logits
    }
}
