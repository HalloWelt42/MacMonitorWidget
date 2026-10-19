import WidgetKit
import SwiftUI

// Das echte Schreibtisch-Widget. Das Betriebssystem aktualisiert die Zeitleiste in
// eigenem Takt (wie Wetter), nicht sekündlich. Je Aktualisierung misst der Provider
// einmal über ein kurzes Fenster.

struct SystemEntry: TimelineEntry {
    let date: Date
    let snapshot: SystemSnapshot
}

struct SystemProvider: TimelineProvider {
    func placeholder(in context: Context) -> SystemEntry {
        SystemEntry(date: Date(), snapshot: Self.exampleSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (SystemEntry) -> Void) {
        let snapshot = context.isPreview ? Self.exampleSnapshot : currentSnapshot()
        completion(SystemEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SystemEntry>) -> Void) {
        let entry = SystemEntry(date: Date(), snapshot: currentSnapshot())
        // So bald wie sinnvoll erneut anfragen; das System drosselt nach eigenem Budget.
        let next = Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    // Bevorzugt die vom Programm geteilten Vollwerte; sonst selbst CPU/RAM messen
    // (alles andere ist dem Widget in der Sandbox verwehrt).
    private func currentSnapshot() -> SystemSnapshot {
        SharedStore.read(SystemSnapshot.self, from: .snapshot) ?? SyncSampler.snapshot()
    }

    static var exampleSnapshot: SystemSnapshot {
        var snapshot = SystemSnapshot()
        snapshot.cpu = 0.38
        snapshot.ramFraction = 0.64
        snapshot.ramUsedBytes = 11_000_000_000
        snapshot.ramTotalBytes = 16_000_000_000
        snapshot.gpu = 0.21
        snapshot.powerWatts = 18.4
        snapshot.cpuWatts = 2.6
        snapshot.gpuWatts = 0.2
        snapshot.temperature = 41
        return snapshot
    }
}

struct SystemWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SystemEntry

    var body: some View {
        // Transparenter Hintergrund: das System legt den eingestellten
        // Transparenz-/Unschärfe-Grad des Schreibtisch-Widgets darunter.
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            WidgetSmall(snapshot: entry.snapshot)
        case .systemMedium:
            WidgetMedium(snapshot: entry.snapshot)
        default:
            WidgetLarge(snapshot: entry.snapshot)
        }
    }
}

struct SystemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tech.macmonitorwidget.widget", provider: SystemProvider()) { entry in
            SystemWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MacMonitorWidget")
        .description("CPU, RAM, GPU, Energie und Temperatur auf dem Schreibtisch.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct WidgetsBundle: WidgetBundle {
    var body: some Widget {
        SystemWidget()
        ChipWidget()
    }
}
