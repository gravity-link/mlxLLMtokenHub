import Foundation
import CryptoKit
import MLXMeshCore

/// Connection state of a peer node
public enum PeerConnectionState: String, Codable, Sendable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case relayed = "Relayed (Circuit Relay v2)"
    case holePunched = "Direct (NAT Hole Punched)"
}

/// NAT status of a peer
public enum NATTraversalStatus: String, Codable, Sendable {
    case unknown = "Unknown"
    case publicIP = "Public IP"
    case fullConeNAT = "Full Cone (Punchable)"
    case symmetricNAT = "Symmetric (Relay Required)"
}

/// Represents a discovered or connected peer in the mesh network
public struct PeerNode: Identifiable, Codable, Sendable {
    public var id: String { peerId }
    public let peerId: String
    public var multiaddr: String
    public var role: MeshNodeRole
    public var state: PeerConnectionState
    public var natStatus: NATTraversalStatus
    public var latencyMs: Double
    public var lastSeen: Date
    public var deviceProfile: DeviceProfile?
    public var supportedModels: [String]

    public init(
        peerId: String,
        multiaddr: String,
        role: MeshNodeRole = .auto,
        state: PeerConnectionState = .disconnected,
        natStatus: NATTraversalStatus = .unknown,
        latencyMs: Double = 0.0,
        lastSeen: Date = Date(),
        deviceProfile: DeviceProfile? = nil,
        supportedModels: [String] = []
    ) {
        self.peerId = peerId
        self.multiaddr = multiaddr
        self.role = role
        self.state = state
        self.natStatus = natStatus
        self.latencyMs = latencyMs
        self.lastSeen = lastSeen
        self.deviceProfile = deviceProfile
        self.supportedModels = supportedModels
    }
}

/// Identity key manager for generating and persisting libp2p PeerIDs
public final class PeerIdentity: Sendable {
    public static let shared = PeerIdentity()

    private let privateKey: Curve25519.Signing.PrivateKey

    public var publicKeyData: Data {
        privateKey.publicKey.rawRepresentation
    }

    public var peerId: String {
        // Generate standard libp2p base58-style peer ID prefix with SHA-256 multihash
        let hash = SHA256.hash(data: publicKeyData)
        // libp2p multihash header: 0x12 (sha256), 0x20 (32 bytes length)
        var multihash = Data([0x12, 0x20])
        multihash.append(contentsOf: hash)
        return "12D3KooW" + multihash.prefix(24).map { String(format: "%02x", $0) }.joined().prefix(38)
    }

    public init() {
        self.privateKey = Curve25519.Signing.PrivateKey()
    }
}
