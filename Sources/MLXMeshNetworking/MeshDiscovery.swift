import Foundation
import Network
import MLXMeshCore

/// Coordinates mesh node discovery, bootstrap registration, and NAT traversal
public final class MeshDiscovery: @unchecked Sendable {
    public let bootstrapMultiaddr: Multiaddr
    public let transport: QUICMeshTransport
    public private(set) var knownPeers: [String: PeerNode] = [:]
    
    private let peerLock = NSLock()
    private var isRegistered = false
    private var heartbeatTimer: Timer?

    public init(
        bootstrapMultiaddr: Multiaddr = Multiaddr("/ip4/159.54.182.31/udp/4001/quic-v1/p2p/12D3KooW0866b920449c0fc0e704cfbd800e00cecdaee689"),
        transport: QUICMeshTransport
    ) {
        self.bootstrapMultiaddr = bootstrapMultiaddr
        self.transport = transport
    }

    /// Register this node with the OCI bootstrap relay node
    public func registerWithBootstrap(
        deviceProfile: DeviceProfile,
        assignedRole: MeshNodeRole,
        supportedModels: [String],
        supportedCompression: [CompressionMode] = [.fp8_e4m3, .int8, .topkLogits]
    ) async throws {
        print("[MeshDiscovery] Registering with bootstrap node at \(bootstrapMultiaddr)...")

        final class SafeContinuation: @unchecked Sendable {
            private let lock = NSLock()
            private var isFinished = false
            func resume(continuation: CheckedContinuation<Void, Error>, with result: Result<Void, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !isFinished else { return }
                isFinished = true
                continuation.resume(with: result)
            }
        }

        let guardObj = SafeContinuation()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.transport.connect(to: self.bootstrapMultiaddr) { [weak self] result in
                        guard let self = self else { return }
                        switch result {
                        case .success(let connection):
                            let handshake = HandshakePayload(
                                peerId: self.transport.localPeerId,
                                deviceProfile: deviceProfile,
                                assignedRole: assignedRole,
                                supportedModels: supportedModels,
                                supportedCompressionModes: supportedCompression,
                                libp2pListenAddrs: ["/ip4/0.0.0.0/udp/\(self.transport.listenPort)/quic-v1/p2p/\(self.transport.localPeerId)"]
                            )
                            let packet = MeshPacket(
                                senderPeerId: self.transport.localPeerId,
                                payload: .handshake(handshake)
                            )

                            Task {
                                do {
                                    try await self.transport.send(packet: packet, to: connection)
                                    self.isRegistered = true
                                    print("[MeshDiscovery] Successfully registered with bootstrap relay node!")
                                    guardObj.resume(continuation: continuation, with: .success(()))
                                } catch {
                                    guardObj.resume(continuation: continuation, with: .failure(error))
                                }
                            }

                        case .failure(let error):
                            print("[MeshDiscovery] Failed to connect to bootstrap node: \(error)")
                            guardObj.resume(continuation: continuation, with: .failure(error))
                        }
                    }
                }
            }

            // 4.0-second timeout for registration
            group.addTask {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                throw NSError(domain: "MeshDiscovery", code: -99, userInfo: [NSLocalizedDescriptionKey: "Registration timed out, operating in local ad-hoc P2P mesh mode"])
            }

            try await group.next()
            group.cancelAll()
        }
    }

    /// Update peer record upon receiving discovery or heartbeat packet
    public func updatePeer(peerId: String, multiaddr: String, role: MeshNodeRole, latencyMs: Double, profile: DeviceProfile?) {
        peerLock.lock()
        defer { peerLock.unlock() }

        var peer = knownPeers[peerId] ?? PeerNode(peerId: peerId, multiaddr: multiaddr, role: role)
        peer.role = role
        peer.latencyMs = latencyMs
        peer.lastSeen = Date()
        peer.state = .connected
        if let profile = profile {
            peer.deviceProfile = profile
        }
        knownPeers[peerId] = peer
    }

    /// Find an available Drafter peer
    public func selectBestDrafter() -> PeerNode? {
        peerLock.lock()
        defer { peerLock.unlock() }

        return knownPeers.values
            .filter { $0.role == .drafter && $0.state == .connected }
            .sorted { $0.latencyMs < $1.latencyMs }
            .first
    }

    /// Find an available M4 Verifier peer
    public func selectBestVerifier() -> PeerNode? {
        peerLock.lock()
        defer { peerLock.unlock() }

        return knownPeers.values
            .filter { $0.role == .verifier && $0.state == .connected }
            .sorted { ($0.deviceProfile?.computeScore ?? 0) > ($1.deviceProfile?.computeScore ?? 0) }
            .first
    }
}
