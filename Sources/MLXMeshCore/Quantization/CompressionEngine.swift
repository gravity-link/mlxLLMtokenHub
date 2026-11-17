import Foundation
import Accelerate

/// High-performance activation and tensor compression engine for WAN transmission
public final class CompressionEngine: Sendable {
    public static let shared = CompressionEngine()

    public init() {}

    // MARK: - INT8 Quantization

    /// Quantize Float array to symmetric INT8 with scale factor
    public func quantizeToInt8(_ values: [Float], shape: [Int]) -> CompressedTensorPayload {
        guard !values.isEmpty else {
            return CompressedTensorPayload(mode: .int8, shape: shape, scale: 1.0, rawBytes: Data(), originalElementCount: 0)
        }

        // Find absolute maximum
        var maxAbs: Float = 0.0
        vDSP_maxmgv(values, 1, &maxAbs, vDSP_Length(values.count))
        let scale = maxAbs > 0 ? (maxAbs / 127.0) : 1.0

        var int8Buffer = [Int8](repeating: 0, count: values.count)
        let invScale = 1.0 / scale

        for i in 0..<values.count {
            let scaled = values[i] * invScale
            let clamped = max(-128.0, min(127.0, round(scaled)))
            int8Buffer[i] = Int8(clamped)
        }

        let data = int8Buffer.withUnsafeBufferPointer { Data(buffer: $0) }
        return CompressedTensorPayload(
            mode: .int8,
            shape: shape,
            scale: scale,
            zeroPoint: 0.0,
            rawBytes: data,
            originalElementCount: values.count
        )
    }

    /// Dequantize INT8 payload back to Float array
    public func dequantizeFromInt8(_ payload: CompressedTensorPayload) -> [Float] {
        let count = payload.originalElementCount
        guard count > 0 else { return [] }

        var output = [Float](repeating: 0, count: count)
        let scale = payload.scale

        payload.rawBytes.withUnsafeBytes { rawPtr in
            guard let int8Ptr = rawPtr.bindMemory(to: Int8.self).baseAddress else { return }
            for i in 0..<count {
                output[i] = Float(int8Ptr[i]) * scale
            }
        }

        return output
    }

    // MARK: - FP8 (E4M3) Quantization

    // FP8 E4M3 format: 1 sign bit, 4 exponent bits (bias 7), 3 mantissa bits.
    // Max representable magnitude: 448.0
    private static let fp8_e4m3_max: Float = 448.0

    public func quantizeToFP8_E4M3(_ values: [Float], shape: [Int]) -> CompressedTensorPayload {
        guard !values.isEmpty else {
            return CompressedTensorPayload(mode: .fp8_e4m3, shape: shape, scale: 1.0, rawBytes: Data(), originalElementCount: 0)
        }

        var maxAbs: Float = 0.0
        vDSP_maxmgv(values, 1, &maxAbs, vDSP_Length(values.count))
        let scale = maxAbs > 0 ? (maxAbs / Self.fp8_e4m3_max) : 1.0
        let invScale = 1.0 / scale

        var uint8Buffer = [UInt8](repeating: 0, count: values.count)
        for i in 0..<values.count {
            uint8Buffer[i] = floatToFP8_E4M3(values[i] * invScale)
        }

        let data = uint8Buffer.withUnsafeBufferPointer { Data(buffer: $0) }
        return CompressedTensorPayload(
            mode: .fp8_e4m3,
            shape: shape,
            scale: scale,
            zeroPoint: 0.0,
            rawBytes: data,
            originalElementCount: values.count
        )
    }

    public func dequantizeFromFP8_E4M3(_ payload: CompressedTensorPayload) -> [Float] {
        let count = payload.originalElementCount
        guard count > 0 else { return [] }

        var output = [Float](repeating: 0, count: count)
        let scale = payload.scale

        payload.rawBytes.withUnsafeBytes { rawPtr in
            guard let uint8Ptr = rawPtr.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<count {
                output[i] = fp8_E4M3ToFloat(uint8Ptr[i]) * scale
            }
        }

        return output
    }

    // Helper: Float32 to FP8 E4M3
    private func floatToFP8_E4M3(_ x: Float) -> UInt8 {
        if x == 0.0 { return 0 }
        let sign: UInt8 = x < 0 ? 0x80 : 0x00
        let absX = abs(x)

        if absX > Self.fp8_e4m3_max {
            return sign | 0x7E // saturation
        }

        // Deconstruct float bits
        let bits = absX.bitPattern
        let exp = Int((bits >> 23) & 0xFF) - 127
        let mantissa = bits & 0x7FFFFF

        let biasedExp = exp + 7
        if biasedExp <= 0 {
            // Subnormal
            let shift = 1 - biasedExp
            if shift > 3 { return sign }
            let frac = UInt8((mantissa | 0x800000) >> (23 - 3 + shift))
            return sign | (frac & 0x07)
        } else if biasedExp >= 15 {
            return sign | 0x7E
        } else {
            let frac = UInt8(mantissa >> (23 - 3))
            return sign | (UInt8(biasedExp) << 3) | (frac & 0x07)
        }
    }

    // Helper: FP8 E4M3 to Float32
    private func fp8_E4M3ToFloat(_ byte: UInt8) -> Float {
        let sign: Float = (byte & 0x80) != 0 ? -1.0 : 1.0
        let exp = (byte >> 3) & 0x0F
        let mant = byte & 0x07

        if exp == 0 {
            if mant == 0 { return sign * 0.0 }
            // Subnormal: (-1)^sign * 2^(-6) * (mant / 8)
            return sign * pow(2.0, -6.0) * (Float(mant) / 8.0)
        } else if exp == 15 && mant == 7 {
            return Float.nan
        } else {
            // Normal: (-1)^sign * 2^(exp - 7) * (1 + mant / 8)
            return sign * pow(2.0, Float(exp) - 7.0) * (1.0 + Float(mant) / 8.0)
        }
    }

    // MARK: - Top-K Sparse Logits Compression

    /// Compress full vocabulary logits into a sparse Top-K structure
    public func compressTopKLogits(logits: [Float], topK: Int = 16) -> (topKIndices: [Int], quantizedProbs: Data) {
        guard !logits.isEmpty else { return ([], Data()) }

        // Find top-K indices
        let indexed = logits.indices.map { ($0, logits[$0]) }
        let topEntries = indexed.sorted(by: { $0.1 > $1.1 }).prefix(topK)

        let indices = topEntries.map { $0.0 }
        let topVals = topEntries.map { $0.1 }

        // Softmax over top-K for numerical stability
        let maxVal = topVals.first ?? 0.0
        let expVals = topVals.map { exp($0 - maxVal) }
        let sumExp = expVals.reduce(0, +)
        let probs = expVals.map { sumExp > 0 ? ($0 / sumExp) : 0.0 }

        // Quantize probabilities to UInt8 (0..255)
        var uint8Probs = [UInt8](repeating: 0, count: probs.count)
        for (i, p) in probs.enumerated() {
            uint8Probs[i] = UInt8(max(0, min(255, round(p * 255.0))))
        }

        let data = uint8Probs.withUnsafeBufferPointer { Data(buffer: $0) }
        return (indices, data)
    }
}
