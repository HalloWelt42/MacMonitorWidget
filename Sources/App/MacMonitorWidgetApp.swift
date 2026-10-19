import SwiftUI

struct MacMonitorWidgetApp: App {
    @StateObject private var sampler = SystemSampler()
    @StateObject private var config = AppConfig()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(sampler)
                .environmentObject(config)
                .onChange(of: config.intervalSeconds) { _, newValue in
                    sampler.setInterval(newValue)
                }
        } label: {
            MenuBarLabel(snapshot: sampler.snapshot, style: config.menuBarStyle)
        }
        .menuBarExtraStyle(.window)
    }
}
