import Foundation

/// Unique identifier for mesh inference sessions
public typealias SessionId = String

/// The unified packet structure sent over libp2p QUIC streams
public struct MeshPacket: Codable, Sendable {
    public let version: Int
    public let messageId: String
    public let sessionId: SessionId?
    public let senderPeerId: String
    public let timestamp: TimeInterval
    public let payload: MeshPayload

    public init(
        version: Int = 1,
        messageId: String = UUID().uuidString,
        sessionId: SessionId? = nil,
        senderPeerId: String,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        payload: MeshPayload
    ) {
        self.version = version
        self.messageId = messageId
        self.sessionId = sessionId
        self.senderPeerId = senderPeerId
        self.timestamp = timestamp
        self.payload = payload
    }
}

/// Message payload types
public enum MeshPayload: Codable, Sendable {
    case handshake(HandshakePayload)
    case heartbeat(HeartbeatPayload)
    case speculativeDraftRequest(DraftRequestPayload)
    case speculativeDraftResponse(DraftResponsePayload)
    case speculativeVerifyResult(VerifyResultPayload)
    case statusBroadcast(StatusBroadcastPayload)
    case cancel(CancelPayload)
}

public struct HandshakePayload: Codable, Sendable {
    public let peerId: String
    public let deviceProfile: DeviceProfile
    public let assignedRole: MeshNodeRole
    public let supportedModels: [String]
    public let supportedCompressionModes: [CompressionMode]
    public let libp2pListenAddrs: [String]

    public init(
        peerId: String,
        deviceProfile: DeviceProfile,
        assignedRole: MeshNodeRole,
        supportedModels: [String],
        supportedCompressionModes: [CompressionMode],
        libp2pListenAddrs: [String]
    ) {
        self.peerId = peerId
        self.deviceProfile = deviceProfile
        self.assignedRole = assignedRole
        self.supportedModels = supportedModels
        self.supportedCompressionModes = supportedCompressionModes
        self.libp2pListenAddrs = libp2pListenAddrs
    }
}

public struct HeartbeatPayload: Codable, Sendable {
    public let uptimeSeconds: Double
    public let thermalState: String
    public let batteryLevel: Float
    public let isCharging: Bool
    public let activeSessionsCount: Int
    public let verifiedTokensTotal: Int

    public init(
        uptimeSeconds: Double,
        thermalState: String,
        batteryLevel: Float,
        isCharging: Bool,
        activeSessionsCount: Int,
        verifiedTokensTotal: Int
    ) {
        self.uptimeSeconds = uptimeSeconds
        self.thermalState = thermalState
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.activeSessionsCount = activeSessionsCount
        self.verifiedTokensTotal = verifiedTokensTotal
    }
}

/// Request sent to a Drafter node to generate K speculative tokens
public struct DraftRequestPayload: Codable, Sendable {
    public let promptTokens: [Int]
    public let draftTokenCount: Int // e.g. K = 4 or 6
    public let temperature: Float
    public let topP: Float
    public let compressionMode: CompressionMode
    public let kvCacheStartPos: Int

    public init(
        promptTokens: [Int],
        draftTokenCount: Int = 4,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        compressionMode: CompressionMode = .topkLogits,
        kvCacheStartPos: Int = 0
    ) {
        self.promptTokens = promptTokens
        self.draftTokenCount = draftTokenCount
        self.temperature = temperature
        self.topP = topP
        self.compressionMode = compressionMode
        self.kvCacheStartPos = kvCacheStartPos
    }
}

/// Speculative draft candidates returned by the Drafter node
public struct DraftResponsePayload: Codable, Sendable {
    public let draftTokens: [CompressedDraftToken]
    public let durationMs: Double
    public let draftTokensPerSec: Double
    public let compressedActivations: CompressedTensorPayload?

    public init(
        draftTokens: [CompressedDraftToken],
        durationMs: Double,
        draftTokensPerSec: Double,
        compressedActivations: CompressedTensorPayload? = nil
    ) {
        self.draftTokens = draftTokens
        self.durationMs = durationMs
        self.draftTokensPerSec = draftTokensPerSec
        self.compressedActivations = compressedActivations
    }
}

/// Verification result returned by the Verifier node (iPad Pro M4)
public struct VerifyResultPayload: Codable, Sendable {
    /// Number of accepted draft tokens (0 <= acceptedCount <= K)
    public let acceptedCount: Int
    /// The accepted token IDs
    public let acceptedTokenIds: [Int]
    /// The bonus token sampled from the target model's corrected distribution
    public let bonusTokenId: Int?
    /// Whether the end-of-sequence token was encountered
    public let isEOS: Bool
    /// Verification duration on the M4 target model
    public let targetForwardDurationMs: Double
    /// Effective tokens emitted this round (acceptedCount + (bonusToken != nil ? 1 : 0))
    public let totalEmittedTokens: Int
    /// Speculative acceptance rate of this round (acceptedCount / totalDraftCount)
    public let acceptanceRate: Double

    public init(
        acceptedCount: Int,
        acceptedTokenIds: [Int],
        bonusTokenId: Int?,
        isEOS: Bool,
        targetForwardDurationMs: Double,
        totalEmittedTokens: Int,
        acceptanceRate: Double
    ) {
        self.acceptedCount = acceptedCount
        self.acceptedTokenIds = acceptedTokenIds
        self.bonusTokenId = bonusTokenId
        self.isEOS = isEOS
        self.targetForwardDurationMs = targetForwardDurationMs
        self.totalEmittedTokens = totalEmittedTokens
        self.acceptanceRate = acceptanceRate
    }
}

public struct StatusBroadcastPayload: Codable, Sendable {
    public let message: String
    public let activeNodes: Int

    public init(message: String, activeNodes: Int) {
        self.message = message
        self.activeNodes = activeNodes
    }
}

public struct CancelPayload: Codable, Sendable {
    public let reason: String
    public init(reason: String) { self.reason = reason }
}
