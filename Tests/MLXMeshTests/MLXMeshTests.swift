import Testing
@testable import MLXMeshCore
@testable import MLXMeshNetworking
@testable import MLXMeshEngine

@Suite("MLXMesh Test Suite")
struct MLXMeshTests {
    @Test("Device Profile Detection")
    func testDeviceProfile() {
        let profile = DeviceProfile()
        #expect(!profile.deviceName.isEmpty)
        #expect(profile.cpuCores > 0)
        #expect(profile.totalMemoryGB > 0)
    }

    @Test("INT8 Quantization Roundtrip")
    func testINT8() {
        let original: [Float] = [0.0, 1.5, -2.5, 3.1415, -0.75, 4.0]
        let payload = CompressionEngine.shared.quantizeToInt8(original, shape: [1, original.count])
        #expect(payload.mode == .int8)
        let restored = CompressionEngine.shared.dequantizeFromInt8(payload)
        #expect(restored.count == original.count)
    }

    @Test("FP8 Quantization Roundtrip")
    func testFP8() {
        let original: [Float] = [0.0, 1.5, -2.5, 3.1415, -0.75, 10.0]
        let payload = CompressionEngine.shared.quantizeToFP8_E4M3(original, shape: [1, original.count])
        #expect(payload.mode == .fp8_e4m3)
        let restored = CompressionEngine.shared.dequantizeFromFP8_E4M3(payload)
        #expect(restored.count == original.count)
    }

    @Test("Multiaddr Parsing")
    func testMultiaddr() {
        let addr = Multiaddr("/ip4/159.54.182.31/udp/4001/quic-v1/p2p/12D3KooWtest")
        #expect(addr.host == "159.54.182.31")
        #expect(addr.udpPort == 4001)
        #expect(addr.isQUIC)
        #expect(addr.peerId == "12D3KooWtest")
    }

    @Test("Speculative Decoding Engine")
    func testSpeculativeLoop() async {
        let engine = SpeculativeEngine()
        let metrics = await engine.generateStream(prompt: "Hello", maxTokens: 16) { _, _ in }
        #expect(metrics.totalTokensGenerated > 0)
        #expect(metrics.networkRoundTrips > 0)
    }
}
