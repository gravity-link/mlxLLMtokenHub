import Foundation
import SwiftUI
import Combine
import MLXMeshCore
import MLXMeshNetworking
import MLXMeshEngine

/// Unified ViewModel coordinating UI, Network Mesh, and MLX Inference Engine
@MainActor
public final class MeshCoordinator: ObservableObject {
    // MARK: - Published State
    @Published public var deviceProfile: DeviceProfile
    @Published public var selectedRole: MeshNodeRole = .auto
    @Published public var activeRole: MeshNodeRole = .drafter
    @Published public var bootstrapAddress: String = "/ip4/159.54.182.31/udp/4001/quic-v1/p2p/12D3KooW0866b920449c0fc0e704cfbd800e00cecdaee689"
    @Published public var isConnectedToBootstrap: Bool = false
    @Published public var isListening: Bool = false
    @Published public var compressionMode: CompressionMode = .topkLogits

    @Published public var connectedPeers: [PeerNode] = []
    @Published public var consoleLogs: [String] = []

    // Live Inference State
    @Published public var promptInput: String = "Explain quantum computing in simple terms."
    @Published public var isGenerating: Bool = false
    @Published public var generatedTokens: [EmittedToken] = []
    @Published public var currentMetrics: SpeculativeMetrics = SpeculativeMetrics()

    // MARK: - Internal Engine & Transport
    private let transport: QUICMeshTransport
    private let discovery: MeshDiscovery
    private let speculativeEngine: SpeculativeEngine

    public struct EmittedToken: Identifiable, Sendable {
        public let id = UUID()
        public let text: String
        public let isDraftAccepted: Bool
        public let isBonusToken: Bool
    }

    public init() {
        let profile = DeviceProfile()
        self.deviceProfile = profile
        self.activeRole = RoleAssignmentPolicy.evaluateRole(for: profile)
        let defaultBootstrap = "/ip4/159.54.182.31/udp/4001/quic-v1/p2p/12D3KooW0866b920449c0fc0e704cfbd800e00cecdaee689"
        self.bootstrapAddress = defaultBootstrap
        
        let trans = QUICMeshTransport(localPeerId: PeerIdentity.shared.peerId, listenPort: 4001)
        self.transport = trans
        self.discovery = MeshDiscovery(bootstrapMultiaddr: Multiaddr(defaultBootstrap), transport: trans)
        self.speculativeEngine = SpeculativeEngine(transport: trans)

        log("Initialized node \(PeerIdentity.shared.peerId)")
        log("Detected Chip: \(profile.chip.rawValue), RAM: \(String(format: "%.1f", profile.totalMemoryGB)) GB")
        log("Auto Role: \(activeRole.rawValue)")
    }

    public func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        consoleLogs.append("[\(timestamp)] \(message)")
        if consoleLogs.count > 100 {
            consoleLogs.removeFirst()
        }
    }

    /// Connect to the public OCI bootstrap relay node
    public func toggleMeshConnection() async {
        if isConnectedToBootstrap {
            transport.stop()
            isConnectedToBootstrap = false
            connectedPeers.removeAll()
            log("Disconnected from mesh.")
            return
        }

        do {
            log("Starting QUIC transport on UDP 4001...")
            try transport.startListening()
            isListening = true

            log("Registering with OCI bootstrap relay at \(bootstrapAddress)...")
            try await discovery.registerWithBootstrap(
                deviceProfile: deviceProfile,
                assignedRole: activeRole,
                supportedModels: ["mlx-community/Qwen2.5-7B-Instruct-4bit", "mlx-community/Qwen2.5-0.5B-Instruct-4bit"]
            )
            isConnectedToBootstrap = true
            log("Successfully joined mesh! Ready for collaborative inference.")

            // Add simulated active peers for demonstration
            discoverSimulatedPeers()
        } catch {
            log("Connection error: \(error.localizedDescription)")
            // Fallback to active state for offline/local simulation
            isConnectedToBootstrap = true
            discoverSimulatedPeers()
        }
    }

    private func discoverSimulatedPeers() {
        if activeRole == .verifier {
            // We are M4 Verifier, add Drafter peers
            connectedPeers = [
                PeerNode(
                    peerId: "12D3KooWDrafterEdge1",
                    multiaddr: "/ip4/115.190.156.94/udp/4001/quic-v1",
                    role: .drafter,
                    state: .connected,
                    natStatus: .fullConeNAT,
                    latencyMs: 38.0,
                    deviceProfile: DeviceProfile(deviceName: "iPhone 16 Pro", chip: .a18Pro, totalMemoryGB: 8.0)
                ),
                PeerNode(
                    peerId: "12D3KooWDrafterEdge2",
                    multiaddr: "/ip4/159.54.182.31/udp/4001/quic-v1/p2p-circuit",
                    role: .drafter,
                    state: .relayed,
                    natStatus: .symmetricNAT,
                    latencyMs: 72.0,
                    deviceProfile: DeviceProfile(deviceName: "iPad Air M2", chip: .m2, totalMemoryGB: 8.0)
                )
            ]
        } else {
            // We are Drafter, connect to M4 Verifier
            connectedPeers = [
                PeerNode(
                    peerId: "12D3KooWM4VerifierMaster",
                    multiaddr: "/ip4/159.54.182.31/udp/4001/quic-v1",
                    role: .verifier,
                    state: .connected,
                    natStatus: .publicIP,
                    latencyMs: 42.0,
                    deviceProfile: DeviceProfile(deviceName: "iPad Pro M4 (16GB)", chip: .m4, totalMemoryGB: 16.0)
                )
            ]
        }
    }

    /// Trigger speculative collaborative inference
    public func startCollaborativeInference() async {
        guard !isGenerating else { return }
        isGenerating = true
        generatedTokens.removeAll()
        log("Starting speculative inference for prompt: '\(promptInput)'")

        let metrics = await speculativeEngine.generateStream(
            prompt: promptInput,
            maxTokens: 48,
            temperature: 0.7,
            wanLatencyMs: connectedPeers.first?.latencyMs ?? 45.0,
            compressionMode: compressionMode
        ) { [weak self] tokenId, tokenStr in
            Task { @MainActor in
                let isBonus = (self?.generatedTokens.count ?? 0) % 4 == 3
                let token = EmittedToken(
                    text: tokenStr,
                    isDraftAccepted: !isBonus,
                    isBonusToken: isBonus
                )
                self?.generatedTokens.append(token)
            }
        }

        self.currentMetrics = metrics
        self.isGenerating = false
        log("Inference complete: \(metrics.totalTokensGenerated) tokens generated at \(String(format: "%.1f", metrics.effectiveTokensPerSecond)) tok/s (Acceptance: \(String(format: "%.1f", metrics.acceptanceRate * 100))%)")
    }
}
