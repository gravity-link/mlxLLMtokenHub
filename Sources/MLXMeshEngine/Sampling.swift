import Foundation
import Accelerate

/// Speculative sampling and distribution evaluation
public struct SpeculativeSampler: Sendable {
    /// Evaluates speculative acceptance of a draft token given target and draft probabilities
    public static func evaluateAcceptance(
        draftTokenId: Int,
        targetLogits: [Float],
        draftProbability: Float,
        temperature: Float = 0.7
    ) -> (accepted: Bool, targetArgmax: Int) {
        guard !targetLogits.isEmpty else { return (false, 0) }

        // Find argmax for target
        var maxVal: Float = -Float.greatestFiniteMagnitude
        var argmaxIndex: vDSP_Length = 0
        vDSP_maxvi(targetLogits, 1, &maxVal, &argmaxIndex, vDSP_Length(targetLogits.count))
        let targetArgmax = Int(argmaxIndex)

        // For greedy / low temperature: strict equality with target argmax
        if temperature < 0.05 {
            return (draftTokenId == targetArgmax, targetArgmax)
        }

        // Stochastic rejection sampling:
        // Calculate target probability for the draft token
        let targetProb = calculateProbability(for: draftTokenId, in: targetLogits, temperature: temperature)
        let ratio = draftProbability > 0 ? (targetProb / draftProbability) : 0.0

        if ratio >= 1.0 {
            return (true, targetArgmax)
        } else {
            let u = Float.random(in: 0.0...1.0)
            return (u < ratio, targetArgmax)
        }
    }

    private static func calculateProbability(for index: Int, in logits: [Float], temperature: Float) -> Float {
        guard index >= 0 && index < logits.count else { return 0.0 }
        let scaled = logits.map { $0 / temperature }
        let maxVal = scaled.max() ?? 0.0
        let exps = scaled.map { exp($0 - maxVal) }
        let sumExp = exps.reduce(0, +)
        return sumExp > 0 ? (exps[index] / sumExp) : 0.0
    }

    /// Sample next bonus token from modified residual distribution
    public static func sampleResidualToken(targetLogits: [Float], temperature: Float = 0.7) -> Int {
        guard !targetLogits.isEmpty else { return 0 }
        if temperature < 0.05 {
            var maxVal: Float = 0
            var maxIdx: vDSP_Length = 0
            vDSP_maxvi(targetLogits, 1, &maxVal, &maxIdx, vDSP_Length(targetLogits.count))
            return Int(maxIdx)
        }

        let scaled = targetLogits.map { $0 / temperature }
        let maxVal = scaled.max() ?? 0.0
        let exps = scaled.map { exp($0 - maxVal) }
        let sumExp = exps.reduce(0, +)
        let probs = exps.map { sumExp > 0 ? ($0 / sumExp) : 0.0 }

        let rand = Float.random(in: 0.0...1.0)
        var cumulative: Float = 0.0
        for (i, p) in probs.enumerated() {
            cumulative += p
            if rand <= cumulative {
                return i
            }
        }
        return probs.count - 1
    }
}
