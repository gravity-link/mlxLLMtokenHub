import Foundation

/// Compression mode for activation and tensor transfers across WAN
public enum CompressionMode: String, Codable, Sendable {
    case none = "None (FP16/FP32)"
    case fp8_e4m3 = "FP8 (E4M3)"
    case fp8_e5m2 = "FP8 (E5M2)"
    case int8 = "INT8 Symmetric"
    case topkLogits = "Top-K Sparse Logits"
}

/// Compact compressed tensor or activation slice over the wire
public struct CompressedTensorPayload: Codable, Sendable {
    public let mode: CompressionMode
    public let shape: [Int]
    public let scale: Float
    public let zeroPoint: Float
    public let rawBytes: Data
    public let originalElementCount: Int

    public init(
        mode: CompressionMode,
        shape: [Int],
        scale: Float,
        zeroPoint: Float = 0.0,
        rawBytes: Data,
        originalElementCount: Int
    ) {
        self.mode = mode
        self.shape = shape
        self.scale = scale
        self.zeroPoint = zeroPoint
        self.rawBytes = rawBytes
        self.originalElementCount = originalElementCount
    }
}

/// Compressed candidate token prediction with sparse top-k logits
public struct CompressedDraftToken: Codable, Sendable {
    public let tokenId: Int
    /// Top-K candidate alternative tokens and their quantized probabilities (0-255)
    public let topKTokenIds: [Int]?
    public let topKProbabilities: Data? // Quantized uint8 probabilities
    public let confidence: Float

    public init(
        tokenId: Int,
        topKTokenIds: [Int]? = nil,
        topKProbabilities: Data? = nil,
        confidence: Float = 1.0
    ) {
        self.tokenId = tokenId
        self.topKTokenIds = topKTokenIds
        self.topKProbabilities = topKProbabilities
        self.confidence = confidence
    }
}
