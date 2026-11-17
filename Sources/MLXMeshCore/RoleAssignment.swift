import Foundation

/// Defines the node's functional role in the federated inference mesh
public enum MeshNodeRole: String, Codable, Sendable, CaseIterable {
    /// M4 / High-memory node that runs the large Target Model (e.g. 7B/8B/14B Q4)
    /// Performs batch verification on draft tokens in a single parallel forward pass
    case verifier = "Verifier"

    /// Lightweight node (A-series or smaller iPads) running the Draft Model (e.g. 0.5B/1.5B Q4)
    /// Emits fast speculative draft sequences
    case drafter = "Drafter"

    /// Orchestrates prompt routing, node discovery, benchmark metrics, and mesh consensus
    case orchestrator = "Orchestrator"

    /// Auto-determined role based on chip capability, battery, and network conditions
    case auto = "Auto"
}

/// Dynamic role assignment policy
public struct RoleAssignmentPolicy: Sendable {
    /// Determines the optimal role for a given device profile
    public static func evaluateRole(for profile: DeviceProfile, existingVerifierCount: Int = 0) -> MeshNodeRole {
        // If device has M4 or high compute score and thermal state is nominal
        let isM4 = profile.chip == .m4 || profile.chip == .m4Pro || profile.chip == .m4Max
        let hasSufficientMemory = profile.totalMemoryGB >= 12.0 // iPad Pro M4 with 16GB or 12GB+
        let isHealthyThermal = profile.thermalState.lowercased() == "nominal" || profile.thermalState.lowercased() == "fair"
        
        if (isM4 || profile.chip.isVerifierCapable) && hasSufficientMemory && isHealthyThermal {
            // M4 node is the ideal Verifier
            return .verifier
        } else {
            // Smaller devices act as Drafters
            return .drafter
        }
    }
}
