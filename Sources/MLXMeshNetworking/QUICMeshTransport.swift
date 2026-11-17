import Foundation
import Network
import MLXMeshCore

/// Event listener callback protocol for mesh networking
public protocol QUICMeshTransportDelegate: AnyObject, Sendable {
    func transportDidReceivePacket(_ packet: MeshPacket, from connection: NWConnection)
    func transportPeerConnected(_ peerId: String, connection: NWConnection)
    func transportPeerDisconnected(_ peerId: String)
}

/// QUIC transport implementation using Apple Network.framework
public final class QUICMeshTransport: @unchecked Sendable {
    public let localPeerId: String
    public var listenPort: UInt16
    public weak var delegate: QUICMeshTransportDelegate?

    private var listener: NWListener?
    private var activeConnections: [String: NWConnection] = [:]
    private let connectionQueue = DispatchQueue(label: "com.mlxmesh.transport.queue", attributes: .concurrent)
    private var isRunning: Bool = false

    public init(localPeerId: String = PeerIdentity.shared.peerId, listenPort: UInt16 = 4001) {
        self.localPeerId = localPeerId
        self.listenPort = listenPort
    }

    /// Creates Apple Network.framework parameters configured for libp2p QUIC
    private func createQUICParameters() -> NWParameters {
        let options = NWProtocolQUIC.Options(alpn: ["libp2p", "mlx-mesh"])
        options.isDatagram = false
        options.maxDatagramFrameSize = 65535
        
        let secOptions = options.securityProtocolOptions
        sec_protocol_options_set_verify_block(secOptions, { _, sec_trust, completionHandler in
            // For P2P mesh, we authenticate peer identity via signed libp2p envelopes
            completionHandler(true)
        }, connectionQueue)

        let parameters = NWParameters(quic: options)
        parameters.includePeerToPeer = true
        parameters.prohibitExpensivePaths = false
        parameters.prohibitConstrainedPaths = false
        parameters.serviceClass = .responsiveData
        return parameters
    }

    /// Start listening for incoming QUIC connections
    public func startListening() throws {
        let params = createQUICParameters()
        guard let port = NWEndpoint.Port(rawValue: listenPort) else {
            throw NSError(domain: "QUICMeshTransport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }

        let newListener = try NWListener(using: params, on: port)
        self.listener = newListener

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.isRunning = true
                print("[QUIC Transport] Listening on UDP port \(self.listenPort) (QUIC-v1)")
            case .failed(let error):
                print("[QUIC Transport] Listener failed: \(error)")
                self.isRunning = false
            case .cancelled:
                self.isRunning = false
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingConnection(connection)
        }

        newListener.start(queue: connectionQueue)
    }

    /// Connect to a remote peer via QUIC multiaddress
    public func connect(to multiaddr: Multiaddr, completion: (@Sendable (Result<NWConnection, Error>) -> Void)? = nil) {
        guard let host = multiaddr.host, let port = multiaddr.udpPort else {
            completion?(.failure(NSError(domain: "QUICMeshTransport", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid host or UDP port in multiaddress"])))
            return
        }

        let endpointHost = NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            completion?(.failure(NSError(domain: "QUICMeshTransport", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid UDP port"])))
            return
        }

        let params = createQUICParameters()
        let connection = NWConnection(host: endpointHost, port: endpointPort, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("[QUIC Transport] Outgoing QUIC connection ready to \(host):\(port)")
                let peerKey = multiaddr.peerId ?? "\(host):\(port)"
                self.connectionQueue.async(flags: .barrier) {
                    self.activeConnections[peerKey] = connection
                }
                self.startReading(from: connection, peerKey: peerKey)
                completion?(.success(connection))
            case .failed(let error):
                print("[QUIC Transport] Connection failed to \(host):\(port): \(error)")
                completion?(.failure(error))
            default:
                break
            }
        }

        connection.start(queue: connectionQueue)
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                let endpointStr = "\(connection.endpoint)"
                print("[QUIC Transport] Accepted incoming QUIC connection from \(endpointStr)")
                self.connectionQueue.async(flags: .barrier) {
                    self.activeConnections[endpointStr] = connection
                }
                self.startReading(from: connection, peerKey: endpointStr)
            case .cancelled, .failed:
                let endpointStr = "\(connection.endpoint)"
                self.connectionQueue.async(flags: .barrier) {
                    self.activeConnections.removeValue(forKey: endpointStr)
                }
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
    }

    /// Read length-prefixed packet stream
    private func startReading(from connection: NWConnection, peerKey: String) {
        // Read 4-byte header length
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                print("[QUIC Transport] Receive header error: \(error)")
                self.delegate?.transportPeerDisconnected(peerKey)
                return
            }

            guard let data = content, data.count == 4 else {
                if isComplete {
                    self.delegate?.transportPeerDisconnected(peerKey)
                }
                return
            }

            let payloadLength = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.readPayload(from: connection, peerKey: peerKey, length: Int(payloadLength))
        }
    }

    private func readPayload(from connection: NWConnection, peerKey: String, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                print("[QUIC Transport] Receive payload error: \(error)")
                return
            }

            if let payloadData = content {
                do {
                    let packet = try JSONDecoder().decode(MeshPacket.self, from: payloadData)
                    self.delegate?.transportDidReceivePacket(packet, from: connection)
                } catch {
                    print("[QUIC Transport] Failed to decode packet: \(error)")
                }
            }

            if !isComplete {
                self.startReading(from: connection, peerKey: peerKey)
            }
        }
    }

    /// Send a packet over an existing QUIC connection
    public func send(packet: MeshPacket, to connection: NWConnection) async throws {
        let payloadData = try JSONEncoder().encode(packet)
        var length = UInt32(payloadData.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(payloadData)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Broadcast packet to all connected peers
    public func broadcast(packet: MeshPacket) async {
        let connections = connectionQueue.sync { Array(activeConnections.values) }
        for conn in connections {
            try? await send(packet: packet, to: conn)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        connectionQueue.sync(flags: .barrier) {
            for (_, conn) in activeConnections {
                conn.cancel()
            }
            activeConnections.removeAll()
        }
        isRunning = false
    }
}
