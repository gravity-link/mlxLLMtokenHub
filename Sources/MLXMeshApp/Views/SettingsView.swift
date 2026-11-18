import SwiftUI
import MLXMeshCore

public struct SettingsView: View {
    @ObservedObject var coordinator: MeshCoordinator

    public init(coordinator: MeshCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Node Role & Partitioning")) {
                    Picker("Assigned Role", selection: $coordinator.selectedRole) {
                        ForEach(MeshNodeRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .onChange(of: coordinator.selectedRole) { _, newRole in
                        if newRole == .auto {
                            coordinator.activeRole = RoleAssignmentPolicy.evaluateRole(for: coordinator.deviceProfile)
                        } else {
                            coordinator.activeRole = newRole
                        }
                    }

                    HStack {
                        Text("Active Operating Role")
                        Spacer()
                        Text(coordinator.activeRole.rawValue)
                            .foregroundColor(coordinator.activeRole == .verifier ? .purple : .blue)
                            .fontWeight(.semibold)
                    }

                    if coordinator.activeRole == .verifier {
                        Text("This node validates speculative draft tokens in a single parallel batch forward pass on the M4 GPU.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("This node generates speculative draft candidates and forwards them over QUIC for remote verification.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Model Deployment & Weights (模型部署与权重)")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Compute Role:")
                            Spacer()
                            Text(coordinator.activeRole == .verifier ? "Verifier (Target Model)" : "Drafter (Draft Model)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(coordinator.activeRole == .verifier ? .purple : .blue)
                        }

                        HStack {
                            Text("Draft Model (0.5B):")
                            Spacer()
                            Text(coordinator.activeDraftModel.split(separator: "/").last ?? "Qwen2.5-0.5B")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Target Model (7B):")
                            Spacer()
                            Text(coordinator.activeTargetModel.split(separator: "/").last ?? "Qwen2.5-7B")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        if coordinator.isDownloading {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: coordinator.downloadProgress)
                                    .progressViewStyle(.linear)
                                Text("Deploying model weights... \(Int(coordinator.downloadProgress * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            HStack {
                                Button(action: {
                                    Task {
                                        await coordinator.deploySmallModel("mlx-community/Qwen2.5-0.5B-Instruct-4bit")
                                    }
                                }) {
                                    Label("Deploy Small Model (Qwen2.5-0.5B)", systemImage: "arrow.down.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)

                                Spacer()

                                if coordinator.isModelLoaded {
                                    Text("Ready")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("libp2p-quic Bootstrap & Relay")) {
                    TextField("Bootstrap Multiaddress", text: $coordinator.bootstrapAddress)
                        .font(.system(.footnote, design: .monospaced))

                    Text("Default: OCI Public Server (`/ip4/159.54.182.31/udp/4001/quic-v1/p2p/12D3KooW0866b920449c0fc0e704cfbd800e00cecdaee689`). Provides Circuit Relay v2 and AutoNAT rendezvous.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Public Network Communication Compression")) {
                    Picker("Compression Algorithm", selection: $coordinator.compressionMode) {
                        Text("Top-K Sparse Logits (99.8% reduction)").tag(CompressionMode.topkLogits)
                        Text("INT8 Symmetric Quantization").tag(CompressionMode.int8)
                        Text("FP8 (E4M3) Quantization").tag(CompressionMode.fp8_e4m3)
                        Text("FP8 (E5M2) Quantization").tag(CompressionMode.fp8_e5m2)
                        Text("None (FP16/FP32 Raw)").tag(CompressionMode.none)
                    }

                    Text("Quantizes candidate token distributions and activation residuals before wire transmission, minimizing WAN ping impact.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Mesh Settings")
        }
    }
}
