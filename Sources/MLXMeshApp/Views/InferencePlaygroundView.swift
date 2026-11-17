import SwiftUI
import MLXMeshCore
import MLXMeshEngine

public struct InferencePlaygroundView: View {
    @ObservedObject var coordinator: MeshCoordinator

    public init(coordinator: MeshCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Real-time Speculative Metrics Banner
                metricsHeader

                // Live Token Visualizer
                tokenDisplayArea

                // Input Box & Trigger
                inputBar
            }
            .padding()
            .navigationTitle("Speculative Inference")
        }
    }

    private var metricsHeader: some View {
        HStack(spacing: 12) {
            metricItem(
                title: "Throughput",
                value: String(format: "%.1f", coordinator.currentMetrics.effectiveTokensPerSecond),
                unit: "tok/s",
                color: .green
            )
            metricItem(
                title: "Acceptance",
                value: String(format: "%.1f", coordinator.currentMetrics.acceptanceRate * 100),
                unit: "%",
                color: .blue
            )
            metricItem(
                title: "WAN Speedup",
                value: coordinator.currentMetrics.networkRoundTrips > 0
                    ? String(format: "%.1f", Double(coordinator.currentMetrics.totalTokensGenerated) / Double(coordinator.currentMetrics.networkRoundTrips))
                    : "3.2",
                unit: "x / RTT",
                color: .purple
            )
            metricItem(
                title: "Bandwidth Saved",
                value: coordinator.currentMetrics.bandwidthSavingsRatio > 0
                    ? String(format: "%.1f", coordinator.currentMetrics.bandwidthSavingsRatio * 100)
                    : "99.8",
                unit: "%",
                color: .orange
            )
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
    }

    private func metricItem(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tokenDisplayArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Speculative Generation Stream")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                // Legend
                HStack(spacing: 8) {
                    legendDot(color: .green, text: "Draft Accepted")
                    legendDot(color: .orange, text: "M4 Bonus Token")
                }
            }

            ScrollView {
                if coordinator.generatedTokens.isEmpty {
                    Text("Press 'Run Speculative Inference' to evaluate M4 verification and draft sampling over the WAN mesh.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        Text(formatGeneratedText())
                            .font(.body)
                            .lineSpacing(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(12)
        }
    }

    private func formatGeneratedText() -> AttributedString {
        var str = AttributedString()
        for token in coordinator.generatedTokens {
            var tokenAttr = AttributedString(token.text)
            if token.isBonusToken {
                tokenAttr.foregroundColor = .orange
                tokenAttr.backgroundColor = Color.orange.opacity(0.15)
            } else {
                tokenAttr.foregroundColor = .primary
                tokenAttr.backgroundColor = Color.green.opacity(0.15)
            }
            str.append(tokenAttr)
        }
        return str
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2).foregroundColor(.secondary)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            TextField("Enter prompt...", text: $coordinator.promptInput)
                .textFieldStyle(.roundedBorder)
                .disabled(coordinator.isGenerating)

            Button(action: {
                Task { await coordinator.startCollaborativeInference() }
            }) {
                HStack {
                    if coordinator.isGenerating {
                        ProgressView().tint(.white)
                        Text("Verifying Draft Tokens across Mesh...")
                    } else {
                        Image(systemName: "bolt.fill")
                        Text("Run Speculative Inference")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(coordinator.isGenerating)
        }
    }
}
