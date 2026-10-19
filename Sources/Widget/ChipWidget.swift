import WidgetKit
import SwiftUI
import os

// Extragroßes Widget mit der Chip-Übersicht (Auslastung, Takt, Speicher, Leistung
// samt Verlauf). Die Werte misst das laufende Menüleisten-Programm und legt sie
// in der App-Gruppe ab; das Widget zeigt den jeweils jüngsten Stand.

struct ChipEntry: TimelineEntry {
    let date: Date
    let trace: ChipTrace
}

struct ChipProvider: TimelineProvider {
    private static let log = Logger(subsystem: "tech.macmonitorwidget.app.widget", category: "chip")

    func placeholder(in context: Context) -> ChipEntry {
        ChipEntry(date: Date(), trace: currentTrace())
    }

    func getSnapshot(in context: Context, completion: @escaping (ChipEntry) -> Void) {
        completion(ChipEntry(date: Date(), trace: currentTrace()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChipEntry>) -> Void) {
        Self.log.info("Zeitleiste angefragt, Größe \(context.displaySize.width, privacy: .public)x\(context.displaySize.height, privacy: .public)")
        let entry = ChipEntry(date: Date(), trace: currentTrace())
        // So bald wie möglich erneut anfragen; das System drosselt nach eigenem Budget.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }

    private func currentTrace() -> ChipTrace {
        SharedStore.read(ChipTrace.self, from: .chipTrace) ?? ChipTrace()
    }
}

struct ChipWidgetView: View {
    var entry: ChipEntry

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        ChipBoard(trace: entry.trace, version: version)
            .padding(TerminalTheme.widgetPadding)
            // Petrol nur als Tönung: der Systemhintergrund darunter bleibt
            // halbtransparent wie bei den eingebauten Widgets.
            .containerBackground(for: .widget) {
                TerminalTheme.background.opacity(TerminalTheme.widgetTint)
            }
    }
}

struct ChipWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tech.macmonitorwidget.chip", provider: ChipProvider()) { entry in
            ChipWidgetView(entry: entry)
        }
        .configurationDisplayName("MacMonitorWidget Chip")
        .description("Auslastung und Takt der CPU-Cluster und GPU, Speicher und Leistung mit Verlauf.")
        .supportedFamilies([.systemExtraLarge])
        .contentMarginsDisabled()
    }
}
