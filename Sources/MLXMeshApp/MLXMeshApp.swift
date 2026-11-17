import SwiftUI

public struct MLXMeshRootView: View {
    @StateObject private var coordinator = MeshCoordinator()

    public init() {}

    public var body: some View {
        TabView {
            DashboardView(coordinator: coordinator)
                .tabItem {
                    Label("Mesh Node", systemImage: "cpu")
                }

            InferencePlaygroundView(coordinator: coordinator)
                .tabItem {
                    Label("Speculative LLM", systemImage: "bolt.fill")
                }

            SettingsView(coordinator: coordinator)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#if canImport(UIKit)
@main
public struct MLXMeshApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            MLXMeshRootView()
        }
    }
}
#endif
