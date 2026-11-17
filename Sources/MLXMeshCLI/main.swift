import Foundation
import MLXMeshCore
import MLXMeshNetworking
import MLXMeshEngine

@main
struct MLXMeshCLI {
    static func main() async {
        print("==================================================")
        print("  mlxLLM: iPadOS/M4 Speculative Mesh Network Node ")
        print("==================================================")

        let args = CommandLine.arguments

        if args.contains("profile") {
            runProfile()
            return
        }

        if args.contains("quantize-test") {
            runQuantizationTest()
            return
        }

        if args.contains("benchmark") {
            await runBenchmark()
            return
        }

        // Default: Run Profile + Quantization Test + Speculative Simulation
        runProfile()
        runQuantizationTest()
        await runBenchmark()
    }

    static func runProfile() {
        print("\n[1] Hardware & Device Telemetry Profile")
        print("--------------------------------------------------")
        let profile = DeviceProfile()
        print("  • Device Name:         \(profile.deviceName)")
        print("  • Chip Architecture:   \(profile.chip.rawValue)")
        print("  • CPU Cores:           \(profile.cpuCores)")
        print("  • Total Unified RAM:   \(String(format: "%.1f", profile.totalMemoryGB)) GB")
        print("  • Memory Bandwidth:    \(profile.chip.memoryBandwidthGBps) GB/s")
        print("  • Thermal State:       \(profile.thermalState)")
        print("  • Auto-Assigned Role:  \(RoleAssignmentPolicy.evaluateRole(for: profile).rawValue)")
        print("  • Local Peer ID:       \(PeerIdentity.shared.peerId)")
        print("  • Bootstrap Target:    /ip4/159.54.182.31/udp/4001/quic-v1/p2p/12D3KooW0866b920449c0fc0e704cfbd800e00cecdaee689")
    }

    static func runQuantizationTest() {
        print("\n[2] WAN Activation Compression Test (FP8 / INT8)")
        print("--------------------------------------------------")
        let engine = CompressionEngine.shared

        // Generate synthetic activation tensor (1024 floats)
        let count = 1024
        let testFloats: [Float] = (0..<count).map { _ in Float.random(in: -3.5...3.5) }
        let originalBytes = count * MemoryLayout<Float>.size

        // Test INT8 Quantization
        let int8Payload = engine.quantizeToInt8(testFloats, shape: [1, count])
        let int8Bytes = int8Payload.rawBytes.count + MemoryLayout<Float>.size // data + scale
        let int8Savings = (1.0 - Double(int8Bytes) / Double(originalBytes)) * 100.0
        let restoredInt8 = engine.dequantizeFromInt8(int8Payload)
        
        var maxErrorInt8: Float = 0.0
        for i in 0..<count {
            maxErrorInt8 = max(maxErrorInt8, abs(testFloats[i] - restoredInt8[i]))
        }
        print("  • INT8 Symmetric:")
        print("      Original: \(originalBytes) B  --> Compressed: \(int8Bytes) B (\(String(format: "%.1f", int8Savings))% reduction)")
        print("      Max Absolute Quantization Error: \(String(format: "%.4f", maxErrorInt8))")

        // Test FP8 E4M3 Quantization
        let fp8Payload = engine.quantizeToFP8_E4M3(testFloats, shape: [1, count])
        let fp8Bytes = fp8Payload.rawBytes.count + MemoryLayout<Float>.size
        let fp8Savings = (1.0 - Double(fp8Bytes) / Double(originalBytes)) * 100.0
        let restoredFP8 = engine.dequantizeFromFP8_E4M3(fp8Payload)

        var maxErrorFP8: Float = 0.0
        for i in 0..<count {
            maxErrorFP8 = max(maxErrorFP8, abs(testFloats[i] - restoredFP8[i]))
        }
        print("  • FP8 E4M3:")
        print("      Original: \(originalBytes) B  --> Compressed: \(fp8Bytes) B (\(String(format: "%.1f", fp8Savings))% reduction)")
        print("      Max Absolute Quantization Error: \(String(format: "%.4f", maxErrorFP8))")

        // Test Top-K Sparse Logits
        let (topK, probs) = engine.compressTopKLogits(logits: testFloats, topK: 16)
        let topKBytes = topK.count * MemoryLayout<Int>.size + probs.count
        let vocabBytes = count * MemoryLayout<Float>.size
        let topKSavings = (1.0 - Double(topKBytes) / Double(vocabBytes)) * 100.0
        print("  • Top-K Sparse Logits:")
        print("      Full Vocab: \(vocabBytes) B --> Top-16: \(topKBytes) B (\(String(format: "%.1f", topKSavings))% reduction)")
    }

    static func runBenchmark() async {
        print("\n[3] Distributed Speculative Decoding Benchmark")
        print("--------------------------------------------------")
        print("  Simulating: iPad Pro M4 (Target Verifier) <--- WAN QUIC (50ms RTT) ---> Edge Drafter")
        print("  Generating 32 tokens via collaborative speculative sampling...")

        let engine = SpeculativeEngine()
        final class TextCollector: @unchecked Sendable {
            var text = ""
        }
        let collector = TextCollector()

        let metrics = await engine.generateStream(
            prompt: "Artificial Intelligence on Apple Silicon",
            maxTokens: 32,
            temperature: 0.7,
            wanLatencyMs: 50.0,
            compressionMode: .topkLogits
        ) { tokenId, tokenStr in
            collector.text += tokenStr
        }

        print("\n  [Results]")
        print("  • Total Tokens Emitted:       \(metrics.totalTokensGenerated)")
        print("  • Accepted Draft Tokens:      \(metrics.acceptedDraftTokens)")
        print("  • Bonus Tokens (Target M4):   \(metrics.totalBonusTokens)")
        print("  • Acceptance Rate (alpha):    \(String(format: "%.1f", metrics.acceptanceRate * 100.0))%")
        print("  • Network Roundtrips:         \(metrics.networkRoundTrips)")
        print("  • Speedup over Naive Slicing: \(String(format: "%.2f", Double(metrics.totalTokensGenerated) / Double(metrics.networkRoundTrips)))x tokens/roundtrip")
        print("  • Effective Generation Rate:  \(String(format: "%.1f", metrics.effectiveTokensPerSecond)) tokens/sec")
        print("  • Bandwidth Saved via Comp.:  \(String(format: "%.2f", metrics.bandwidthSavingsRatio * 100.0))%")
        print("--------------------------------------------------\n")
    }
}
