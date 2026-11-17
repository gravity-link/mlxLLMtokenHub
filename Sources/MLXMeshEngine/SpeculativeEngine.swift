import Foundation
import MLXMeshCore
import MLXMeshNetworking

/// Real-time metrics from speculative collaborative inference
public struct SpeculativeMetrics: Sendable {
    public var totalTokensGenerated: Int = 0
    public var acceptedDraftTokens: Int = 0
    public var totalDraftTokensProposed: Int = 0
    public var totalBonusTokens: Int = 0
    public var networkRoundTrips: Int = 0
    public var totalDurationSec: Double = 0.0
    public var effectiveTokensPerSecond: Double = 0.0
    public var acceptanceRate: Double = 0.0
    public var bytesTransferred: Int = 0
    public var uncompressedBytesEquiv: Int = 0
    public var bandwidthSavingsRatio: Double = 0.0

    public init(
        totalTokensGenerated: Int = 0,
        acceptedDraftTokens: Int = 0,
        totalDraftTokensProposed: Int = 0,
        totalBonusTokens: Int = 0,
        networkRoundTrips: Int = 0,
        totalDurationSec: Double = 0.0,
        effectiveTokensPerSecond: Double = 0.0,
        acceptanceRate: Double = 0.0,
        bytesTransferred: Int = 0,
        uncompressedBytesEquiv: Int = 0,
        bandwidthSavingsRatio: Double = 0.0
    ) {
        self.totalTokensGenerated = totalTokensGenerated
        self.acceptedDraftTokens = acceptedDraftTokens
        self.totalDraftTokensProposed = totalDraftTokensProposed
        self.totalBonusTokens = totalBonusTokens
        self.networkRoundTrips = networkRoundTrips
        self.totalDurationSec = totalDurationSec
        self.effectiveTokensPerSecond = effectiveTokensPerSecond
        self.acceptanceRate = acceptanceRate
        self.bytesTransferred = bytesTransferred
        self.uncompressedBytesEquiv = uncompressedBytesEquiv
        self.bandwidthSavingsRatio = bandwidthSavingsRatio
    }
}

/// The unified distributed speculative decoding engine
public final class SpeculativeEngine: @unchecked Sendable {
    public let verifierNode: VerifierNode
    public let drafterNode: DrafterNode
    public let transport: QUICMeshTransport

    public private(set) var metrics = SpeculativeMetrics()

    public init(
        verifierNode: VerifierNode = VerifierNode(),
        drafterNode: DrafterNode = DrafterNode(),
        transport: QUICMeshTransport = QUICMeshTransport()
    ) {
        self.verifierNode = verifierNode
        self.drafterNode = drafterNode
        self.transport = transport
    }

    /// Stream speculative collaborative inference
    /// Yields newly accepted tokens in real time
    public func generateStream(
        prompt: String,
        maxTokens: Int = 64,
        temperature: Float = 0.7,
        wanLatencyMs: Double = 45.0,
        compressionMode: CompressionMode = .topkLogits,
        onTokenEmitted: @Sendable @escaping (Int, String) -> Void
    ) async -> SpeculativeMetrics {
        let startTime = CFAbsoluteTimeGetCurrent()
        metrics = SpeculativeMetrics()

        // Tokenize prompt (simulated vocabulary IDs for demonstration)
        var contextTokens = prompt.utf8.map { Int($0) }
        _ = try? await verifierNode.prefill(promptTokens: contextTokens)

        var emittedCount = 0
        var recentAcceptanceRate = 0.75

        while emittedCount < maxTokens {
            // 1. Calculate dynamic K based on WAN latency and acceptance rate
            let K = AsymmetricPipeline.shared.calculateOptimalDraftCount(
                wanRoundTripTimeMs: wanLatencyMs,
                targetForwardPassMs: 18.0, // M4 fast batch forward
                draftForwardPassMs: 6.0,   // Small draft model step
                recentAcceptanceRate: recentAcceptanceRate
            )

            // 2. Drafter generates K speculative candidate tokens
            let draftResponse = await drafterNode.generateDraft(
                promptTokens: contextTokens,
                draftCount: K,
                temperature: temperature,
                compressionMode: compressionMode
            )
            metrics.totalDraftTokensProposed += K
            metrics.networkRoundTrips += 1

            // Track compression savings
            // Uncompressed: K tokens * 32,000 vocab * 4 bytes/float = ~128KB per round
            let uncompressedSize = K * 32000 * 4
            // Compressed top-K: K * 8 top entries * 5 bytes = 40 * K bytes
            let compressedSize = K * 40 + 16
            metrics.bytesTransferred += compressedSize
            metrics.uncompressedBytesEquiv += uncompressedSize

            // 3. Verifier (M4) validates the batch of K tokens in ONE forward pass
            let verifyResult = await verifierNode.verifyDraftBatch(
                draftTokens: draftResponse.draftTokens,
                temperature: temperature
            )

            // 4. Update metrics and context
            metrics.acceptedDraftTokens += verifyResult.acceptedCount
            recentAcceptanceRate = verifyResult.acceptanceRate

            for tokenId in verifyResult.acceptedTokenIds {
                contextTokens.append(tokenId)
                emittedCount += 1
                let str = String(UnicodeScalar(UInt8(tokenId % 128)))
                onTokenEmitted(tokenId, str)
                if emittedCount >= maxTokens { break }
            }

            if let bonus = verifyResult.bonusTokenId, emittedCount < maxTokens {
                metrics.totalBonusTokens += 1
                contextTokens.append(bonus)
                emittedCount += 1
                let str = String(UnicodeScalar(UInt8(bonus % 128)))
                onTokenEmitted(bonus, str)
            }

            if verifyResult.isEOS {
                break
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        metrics.totalTokensGenerated = emittedCount
        metrics.totalDurationSec = totalTime
        metrics.effectiveTokensPerSecond = totalTime > 0 ? (Double(emittedCount) / totalTime) : 0.0
        metrics.acceptanceRate = metrics.totalDraftTokensProposed > 0 ? (Double(metrics.acceptedDraftTokens) / Double(metrics.totalDraftTokensProposed)) : 0.0
        metrics.bandwidthSavingsRatio = metrics.uncompressedBytesEquiv > 0 ? (1.0 - Double(metrics.bytesTransferred) / Double(metrics.uncompressedBytesEquiv)) : 0.0

        return metrics
    }
}
