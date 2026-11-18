import SwiftUI
import MLXMeshCore
import MLXMeshNetworking

public struct DashboardView: View {
    @ObservedObject var coordinator: MeshCoordinator

    public init(coordinator: MeshCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // M4 Chip & Hardware Telemetry Card
                    hardwareCard

                    // Network Mesh Status Card
                    meshStatusCard

                    // Connected Peers Section
                    peersSection

                    // Live Event Logs
                    consoleSection
                }
                .padding()
            }
            .task {
                if !coordinator.isConnectedToBootstrap {
                    await coordinator.toggleMeshConnection()
                }
            }
            .navigationTitle("mlxLLM Compute Node")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task { await coordinator.toggleMeshConnection() }
                    }) {
                        Label(
                            coordinator.isConnectedToBootstrap ? "Disconnect" : "Join Mesh",
                            systemImage: coordinator.isConnectedToBootstrap ? "antenna.radiowaves.left.and.right" : "network"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(coordinator.isConnectedToBootstrap ? .green : .blue)
                }
            }
        }
    }

    private var hardwareCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundColor(.purple)
                Text(coordinator.deviceProfile.chip.rawValue)
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Text(coordinator.activeRole.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(coordinator.activeRole == .verifier ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2))
                    .foregroundColor(coordinator.activeRole == .verifier ? .purple : .blue)
                    .cornerRadius(8)
            }

            Divider()

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Unified Memory").font(.caption).foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", coordinator.deviceProfile.totalMemoryGB)) GB").font(.headline)
                }
                VStack(alignment: .leading) {
                    Text("Memory Bandwidth").font(.caption).foregroundColor(.secondary)
                    Text("\(Int(coordinator.deviceProfile.chip.memoryBandwidthGBps)) GB/s").font(.headline)
                }
                VStack(alignment: .leading) {
                    Text("Thermal State").font(.caption).foregroundColor(.secondary)
                    Text(coordinator.deviceProfile.thermalState).font(.headline)
                        .foregroundColor(coordinator.deviceProfile.thermalState == "Nominal" ? .green : .orange)
                }
                VStack(alignment: .leading) {
                    Text("Compute Score").font(.caption).foregroundColor(.secondary)
                    Text("\(Int(coordinator.deviceProfile.computeScore))").font(.headline)
                }
            }

            Divider()

            HStack {
                Text("Active Model:").font(.caption).foregroundColor(.secondary)
                Text(coordinator.activeRole == .verifier ? coordinator.activeTargetModel : coordinator.activeDraftModel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.purple)
                Spacer()
                Text(coordinator.isModelLoaded ? "Deployed" : "Ready")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(14)
    }

    private var meshStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(coordinator.isConnectedToBootstrap ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(coordinator.isConnectedToBootstrap ? "Mesh Connected (QUIC-v1)" : "Offline / Standalone")
                    .font(.headline)
                Spacer()
                Text("UDP 4001")
                    .font(.caption)
                    .padding(4)
                    .background(Color.gray.opacity(0.18))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bootstrap Relay Multiaddr:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(coordinator.bootstrapAddress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
            }

            HStack {
                Text("Compression:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(coordinator.compressionMode.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(14)
    }

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Discovered Mesh Peers (\(coordinator.connectedPeers.count))")
                    .font(.headline)
                Spacer()
            }

            if coordinator.connectedPeers.isEmpty {
                Text("No remote peers discovered yet. Connect to the OCI bootstrap relay to auto-mesh.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(coordinator.connectedPeers) { peer in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(peer.deviceProfile?.deviceName ?? peer.peerId.prefix(16).description)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(peer.multiaddr)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(peer.role.rawValue)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(peer.role == .verifier ? .purple : .blue)
                            Text("\(Int(peer.latencyMs)) ms")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(10)
                }
            }
        }
    }

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mesh Event Console")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(coordinator.consoleLogs.indices, id: \.self) { idx in
                        Text(coordinator.consoleLogs[idx])
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)
            .padding(10)
            .background(Color.black.opacity(0.85))
            .cornerRadius(10)
        }
    }
}
