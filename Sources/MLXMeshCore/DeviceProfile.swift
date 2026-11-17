import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Represents the detected Apple Silicon chip architecture
public enum AppleSiliconChip: String, Codable, Sendable {
    case m4Max = "Apple M4 Max"
    case m4Pro = "Apple M4 Pro"
    case m4 = "Apple M4"
    case m3Max = "Apple M3 Max"
    case m3Pro = "Apple M3 Pro"
    case m3 = "Apple M3"
    case m2Max = "Apple M2 Max"
    case m2Pro = "Apple M2 Pro"
    case m2 = "Apple M2"
    case m1Max = "Apple M1 Max"
    case m1Pro = "Apple M1 Pro"
    case m1 = "Apple M1"
    case a18Pro = "Apple A18 Pro"
    case a17Pro = "Apple A17 Pro"
    case a16Bionic = "Apple A16 Bionic"
    case a15Bionic = "Apple A15 Bionic"
    case unknown = "Unknown Apple Silicon"

    /// Estimated unified memory bandwidth in GB/s
    public var memoryBandwidthGBps: Double {
        switch self {
        case .m4Max: return 410.0
        case .m4Pro: return 273.0
        case .m4: return 120.0
        case .m3Max: return 300.0
        case .m3Pro: return 150.0
        case .m3: return 100.0
        case .m2Max: return 400.0
        case .m2Pro: return 200.0
        case .m2: return 100.0
        case .m1Max: return 400.0
        case .m1Pro: return 200.0
        case .m1: return 68.25
        case .a18Pro: return 60.0
        case .a17Pro: return 34.0
        case .a16Bionic: return 25.6
        case .a15Bionic: return 25.6
        case .unknown: return 50.0
        }
    }

    /// Whether this chip has the capability to be a high-performance Verifier
    public var isVerifierCapable: Bool {
        switch self {
        case .m4Max, .m4Pro, .m4, .m3Max, .m3Pro, .m2Max, .m2Pro, .m1Max, .m1Pro:
            return true
        default:
            return false
        }
    }
}

/// Device hardware and resource profile
public struct DeviceProfile: Codable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let chip: AppleSiliconChip
    public let cpuCores: Int
    public let totalMemoryGB: Double
    public var availableMemoryGB: Double
    public var thermalState: String
    public var isCharging: Bool
    public var batteryLevel: Float
    public var computeScore: Double

    public init(
        deviceId: String? = nil,
        deviceName: String? = nil,
        chip: AppleSiliconChip? = nil,
        cpuCores: Int? = nil,
        totalMemoryGB: Double? = nil,
        availableMemoryGB: Double? = nil,
        thermalState: String? = nil,
        isCharging: Bool = true,
        batteryLevel: Float = 1.0,
        computeScore: Double? = nil
    ) {
        let assignedChip = chip ?? DeviceProfile.detectChip()
        let assignedTotalMem = totalMemoryGB ?? DeviceProfile.detectTotalMemoryGB()
        let assignedThermal = thermalState ?? DeviceProfile.currentThermalStateString()

        #if canImport(UIKit)
        let defaultName = UIDevice.current.name
        #else
        let defaultName = Host.current().localizedName ?? "Apple Device"
        #endif
        self.deviceId = deviceId ?? UUID().uuidString
        self.deviceName = deviceName ?? defaultName
        self.chip = assignedChip
        self.cpuCores = cpuCores ?? ProcessInfo.processInfo.activeProcessorCount
        self.totalMemoryGB = assignedTotalMem
        self.availableMemoryGB = availableMemoryGB ?? DeviceProfile.estimateAvailableMemoryGB()
        self.thermalState = assignedThermal
        self.isCharging = isCharging
        self.batteryLevel = batteryLevel

        if let score = computeScore, score > 0 {
            self.computeScore = score
        } else {
            var thermalFactor: Double = 1.0
            let lowerThermal = assignedThermal.lowercased()
            if lowerThermal == "fair" {
                thermalFactor = 0.85
            } else if lowerThermal == "serious" {
                thermalFactor = 0.5
            } else if lowerThermal == "critical" {
                thermalFactor = 0.2
            }

            let powerFactor: Double = isCharging ? 1.0 : (Double(batteryLevel) * 0.8)
            let baseScore = assignedChip.memoryBandwidthGBps * (assignedTotalMem / 8.0)
            self.computeScore = baseScore * thermalFactor * powerFactor
        }
    }

    public static func detectTotalMemoryGB() -> Double {
        let bytes = Double(ProcessInfo.processInfo.physicalMemory)
        return bytes / 1073741824.0
    }

    /// Detects Apple Silicon chip type using sysctl
    public static func detectChip() -> AppleSiliconChip {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var machine = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)
            let brand = String(cString: machine)

            if brand.contains("M4 Max") { return .m4Max }
            if brand.contains("M4 Pro") { return .m4Pro }
            if brand.contains("M4") { return .m4 }
            if brand.contains("M3 Max") { return .m3Max }
            if brand.contains("M3 Pro") { return .m3Pro }
            if brand.contains("M3") { return .m3 }
            if brand.contains("M2 Max") { return .m2Max }
            if brand.contains("M2 Pro") { return .m2Pro }
            if brand.contains("M2") { return .m2 }
            if brand.contains("M1 Max") { return .m1Max }
            if brand.contains("M1 Pro") { return .m1Pro }
            if brand.contains("M1") { return .m1 }
        }

        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr)
            }
        }

        if identifier.contains("iPad16,") { return .m4 }
        if identifier.contains("iPad14,") { return .m2 }
        if identifier.contains("iPhone17,") { return .a18Pro }
        if identifier.contains("iPhone16,") { return .a17Pro }

        return .unknown
    }

    public static func estimateAvailableMemoryGB() -> Double {
        return detectTotalMemoryGB() * 0.65
    }

    public static func currentThermalStateString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Nominal"
        }
    }
}
