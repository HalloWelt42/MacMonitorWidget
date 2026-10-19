import SwiftUI

// Das kleine Symbol oben rechts in der Menüleiste, je nach gewähltem Stil.
struct MenuBarLabel: View {
    let snapshot: SystemSnapshot
    let style: MenuBarStyle

    var body: some View {
        switch style {
        case .cpuPercent:
            Text(Fmt.percent(snapshot.cpu))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        case .cpuLabeled:
            Text("CPU \(Fmt.percent(snapshot.cpu))")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        case .cpuAndRam:
            Text("\(Fmt.percent(snapshot.cpu)) \u{00B7} \(Fmt.percent(snapshot.ramFraction))")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
    }
}
