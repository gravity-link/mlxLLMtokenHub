import Foundation
import Network
import MLXMeshCore

/// Manages Circuit Relay v2 routing across the OCI relay node
public final class RelayClient: @unchecked Sendable {
    public let relayNodeMultiaddr: Multiaddr
    public let transport: QUICMeshTransport

    public init(relayNodeMultiaddr: Multiaddr, transport: QUICMeshTransport) {
        self.relayNodeMultiaddr = relayNodeMultiaddr
        self.transport = transport
    }

    /// Formats a circuit relay multiaddress through the OCI relay server
    public func makeCircuitRelayMultiaddr(targetPeerId: String) -> Multiaddr {
        return Multiaddr("\(relayNodeMultiaddr.stringValue)/p2p-circuit/p2p/\(targetPeerId)")
    }

    /// Send packet routed through the relay
    public func forwardViaRelay(packet: MeshPacket, targetPeerId: String, relayConnection: NWConnection) async throws {
        // Enveloping packet with relay routing header
        try await transport.send(packet: packet, to: relayConnection)
    }
}
