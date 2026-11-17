import Foundation
import MLXMeshCore

/// Asymmetric compute pipeline coordinator
/// Dynamically tunes speculative batch size K based on WAN latency and target acceptance rate
public final class AsymmetricPipeline: Sendable {
    public static let shared = AsymmetricPipeline()

    public init() {}

    /// Calculates optimal draft count K to maximize tokens/second over WAN
    /// K is increased when WAN RTT is high (amortizing network roundtrip)
    /// and tuned according to the M4 target model's acceptance rate (alpha)
    public func calculateOptimalDraftCount(
        wanRoundTripTimeMs: Double,
        targetForwardPassMs: Double,
        draftForwardPassMs: Double,
        recentAcceptanceRate: Double // alpha in [0.0...1.0]
    ) -> Int {
        // Over high-latency WAN (e.g. 50-150ms), each roundtrip is expensive.
        // Expected emitted tokens per roundtrip = alpha * K + 1
        // Expected time per roundtrip = RTT + K * draft_time + target_time
        // We find K in [2...8] that maximizes tokens / second

        var bestK = 4
        var maxThroughput = 0.0

        for candidateK in 2...8 {
            let expectedTokens = recentAcceptanceRate * Double(candidateK) + 1.0
            let expectedTimeSec = (wanRoundTripTimeMs + Double(candidateK) * draftForwardPassMs + targetForwardPassMs) / 1000.0
            let throughput = expectedTimeSec > 0 ? (expectedTokens / expectedTimeSec) : 0.0

            if throughput > maxThroughput {
                maxThroughput = throughput
                bestK = candidateK
            }
        }

        return bestK
    }
}
