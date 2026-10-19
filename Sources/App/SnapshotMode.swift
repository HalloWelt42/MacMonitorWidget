import SwiftUI
import AppKit

// Rendert die echten SwiftUI-Bausteine mit Live-Daten offscreen als PNG. Dient
// der visuellen Kontrolle ohne Bildschirmaufnahme und später dem Erzeugen von
// Vorschaubildern für die Dokumentation.
@MainActor
enum SnapshotMode {
    // Genug Messpunkte, damit die Verläufe der Chip-Übersicht gefüllt sind.
    private static let sampleCount = 60
    private static let sampleInterval: useconds_t = 120_000

    static func run(outputDirectory: String) -> Never {
        _ = NSApplication.shared

        // Etwas Verlauf aufbauen und eine aktuelle Momentaufnahme bilden.
        let chip = ChipInfoReader.read()
        let probe = SystemProbe(chip: chip)
        probe.start()

        var history = MetricHistory()
        var trace = ChipTrace(chip: chip)
        var snapshot = SystemSnapshot()
        for _ in 0..<sampleCount {
            usleep(sampleInterval)
            let measurement = probe.measure()
            snapshot = measurement.snapshot
            history.append(snapshot)
            trace.append(measurement.chipSample)
        }

        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

        let allMetrics: [Metric] = [.cpu, .ram, .gpu, .energy]
        let panelModules: [ModuleConfig] = [
            ModuleConfig(kind: .ringe, metrics: allMetrics, enabled: true),
            ModuleConfig(kind: .balken, metrics: [.cpu, .ram, .energy], enabled: true),
            ModuleConfig(kind: .verlauf, metrics: [.cpu, .energy], enabled: true)
        ]
        let fullList: [Metric] = [.cpu, .ram, .gpu, .energy, .temperature, .fan, .swap]
        let showcaseModules: [ModuleConfig] = [
            ModuleConfig(kind: .ringe, metrics: allMetrics, enabled: true),
            ModuleConfig(kind: .balken, metrics: fullList, enabled: true),
            ModuleConfig(kind: .verlauf, metrics: [.cpu, .gpu, .energy, .temperature], enabled: true),
            ModuleConfig(kind: .minimal, metrics: allMetrics, enabled: true),
            ModuleConfig(kind: .tacho, metrics: [.cpu, .gpu, .temperature], enabled: true)
        ]

        render(PanelPreview(snapshot: snapshot, history: history, modules: panelModules),
               to: "\(outputDirectory)/panel.png", width: 280)
        render(ModulesShowcase(snapshot: snapshot, history: history, modules: showcaseModules),
               to: "\(outputDirectory)/bausteine.png", width: 300)
        render(ConfiguratorView().environmentObject(AppConfig()),
               to: "\(outputDirectory)/konfigurator.png", width: 280)

        // Schreibtisch-Widget in den drei WidgetKit-Größen.
        renderWidget(WidgetSmall(snapshot: snapshot), to: "\(outputDirectory)/widget-klein.png", width: 170, height: 170)
        renderWidget(WidgetMedium(snapshot: snapshot), to: "\(outputDirectory)/widget-mittel.png", width: 360, height: 170)
        renderWidget(WidgetLarge(snapshot: snapshot), to: "\(outputDirectory)/widget-gross.png", width: 360, height: 360)

        // Chip-Übersicht als extragroßes Widget: über einem Schreibtisch-Verlauf
        // (halbtransparent wie im Betrieb) und deckend zum Vergleich mit der Vorlage.
        for (name, size) in [("chip-widget", CGSize(width: 715, height: 340)), ("chip-widget-schmal", CGSize(width: 650, height: 310))] {
            renderChipBoard(trace: trace, to: "\(outputDirectory)/\(name).png", size: size, translucent: true)
        }
        renderChipBoard(trace: trace, to: "\(outputDirectory)/chip-widget-deckend.png",
                        size: CGSize(width: 715, height: 340), translucent: false)

        print("Snapshots geschrieben nach \(outputDirectory)")
        print(String(format: "Werte: CPU %.0f%%  RAM %.0f%%  GPU %@  Energie %@",
                     snapshot.cpu * 100,
                     snapshot.ramFraction * 100,
                     snapshot.gpu.map { String(format: "%.0f%%", $0 * 100) } ?? "n/v",
                     snapshot.powerWatts.map { Fmt.watts($0) } ?? "n/v"))
        exit(0)
    }

    private static func render<V: View>(_ view: V, to path: String, width: CGFloat) {
        let wrapped = view
            .frame(width: width)
            .padding(16)
            .background(Color(hex: 0x1B1B1F))
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("Render fehlgeschlagen: \(path)")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private static func renderChipBoard(trace: ChipTrace, to path: String, size: CGSize, translucent: Bool) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let wallpaper = LinearGradient(colors: [Color(red: 0.32, green: 0.45, blue: 0.62), Color(red: 0.75, green: 0.55, blue: 0.45)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
        let view = ZStack {
            wallpaper
            ZStack {
                if translucent {
                    Rectangle().fill(.ultraThinMaterial)
                    TerminalTheme.background.opacity(TerminalTheme.widgetTint)
                } else {
                    TerminalTheme.background
                }
                ChipBoard(trace: trace, version: version)
                    .padding(TerminalTheme.widgetPadding)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(24)
        }
        .frame(width: size.width + 48, height: size.height + 48)
        .environment(\.colorScheme, .dark)
        write(view, to: path)
    }

    private static func write<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("Render fehlgeschlagen: \(path)")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // Rendert eine Widget-Inhaltsansicht in exakter Widget-Größe mit dunklem Grund.
    private static func renderWidget<V: View>(_ view: V, to path: String, width: CGFloat, height: CGFloat) {
        // Gedämpfter Grund, der ein Wallpaper unter dem transparenten Widget andeutet.
        let wrapped = view
            .padding(16)
            .frame(width: width, height: height)
            .background(Color(red: 0.17, green: 0.19, blue: 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("Render fehlgeschlagen: \(path)")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

// Statische Nachbildung des Panels (ohne Umgebungsobjekte) für das Rendern.
private struct PanelPreview: View {
    let snapshot: SystemSnapshot
    let history: MetricHistory
    let modules: [ModuleConfig]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("MacMonitorWidget").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("1 s").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 10)
            VStack(spacing: 0) {
                ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                    ModuleView(config: module, snapshot: snapshot, history: history)
                        .padding(.vertical, index == 0 ? 0 : 12)
                    if index < modules.count - 1 { Divider() }
                }
            }
            Divider().padding(.vertical, 10)
            HStack {
                Label("Anpassen", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Label("Beenden", systemImage: "power")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ModulesShowcase: View {
    let snapshot: SystemSnapshot
    let history: MetricHistory
    let modules: [ModuleConfig]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(modules) { module in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Image(systemName: module.kind.symbol).font(.system(size: 11))
                        Text(module.kind.title).font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(module.kind.blurb).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    ModuleView(config: module, snapshot: snapshot, history: history)
                }
                .padding(12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
