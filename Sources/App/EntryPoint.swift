import Foundation

// Einstiegspunkt. Mit "--dump" (oder LEITWARTE_DUMP) läuft die App kopflos: sie
// misst einmal, gibt die Werte auf der Konsole aus und beendet sich. So lassen
// sich die Sampler ohne Menüleisten-Klick verifizieren.
@main
enum EntryPoint {
    static func main() {
        let arguments = CommandLine.arguments
        let dumpRequested = arguments.contains("--dump")
            || ProcessInfo.processInfo.environment["LEITWARTE_DUMP"] != nil
        if dumpRequested {
            DumpMode.run()
        }
        if let index = arguments.firstIndex(of: "--snapshot") {
            let directory = arguments.count > index + 1 ? arguments[index + 1] : "/tmp/leitwarte-shots"
            MainActor.assumeIsolated { SnapshotMode.run(outputDirectory: directory) }
        }
        LeitwarteApp.main()
    }
}

enum DumpMode {
    static func run() -> Never {
        let chip = ChipInfoReader.read()
        let probe = SystemProbe(chip: chip)
        probe.start()
        usleep(1_000_000)           // eine Sekunde für ein belastbares Delta
        let measurement = probe.measure()
        let snap = measurement.snapshot
        let sample = measurement.chipSample

        print("== Leitwarte Dump ==")
        print("Chip       : \(chip.headline)")
        print("Takt E/P   : \(mhzList(chip.eFrequencies)) | \(mhzList(chip.pFrequencies))")
        print("Takt GPU   : \(mhzList(chip.gpuFrequencies))")
        print("CPU gesamt : \(Fmt.percent(snap.cpu))")
        let cores = snap.perCore.map { Fmt.percentValue($0) }.joined(separator: " ")
        print("CPU/Kern   : \(cores)")
        print("RAM        : \(Fmt.gib(snap.ramUsedBytes)) / \(Fmt.gibWhole(snap.ramTotalBytes)) (\(Fmt.percent(snap.ramFraction)))")
        print("GPU        : \(snap.gpu.map(Fmt.percent) ?? "n/v")")
        print("Energie    : System \(snap.powerWatts.map(Fmt.watts) ?? "n/v")")
        print("Temperatur : \(snap.temperature.map { String(format: "%.1f \u{00B0}C", $0) } ?? "n/v")")
        print("Swap       : \(Fmt.gib(snap.swapUsedBytes)) / \(Fmt.gibWhole(snap.swapTotalBytes))")
        print("IOReport   : \(probe.ioreport.available ? "verfügbar" : "NICHT verfügbar")")
        if let startError = probe.ioreport.startError {
            print("IOReport-Fehler: \(startError)")
        }

        // Dieselben Felder und Einheiten wie die Rohausgabe des Referenzwerkzeugs,
        // damit sich beide Zeile für Zeile vergleichen lassen.
        print("\n-- Chip-Übersicht (Rohwerte) --")
        print(String(format: "ecpu_usage  : [%.0f, %.4f]", sample.eCluster.mhz, sample.eCluster.usage))
        print(String(format: "pcpu_usage  : [%.0f, %.4f]", sample.pCluster.mhz, sample.pCluster.usage))
        print(String(format: "gpu_usage   : [%.0f, %.4f]", sample.gpu.mhz, sample.gpu.usage))
        print(String(format: "cpu_power   : %.3f W", sample.cpuWatts))
        print(String(format: "gpu_power   : %.3f W", sample.gpuWatts))
        print(String(format: "ane_power   : %.3f W", sample.aneWatts))
        print(String(format: "all_power   : %.3f W", sample.computeWatts))
        print(String(format: "sys_power   : %.3f W", sample.systemWatts ?? 0))
        print("ram_usage   : \(sample.ramUsedBytes) / \(sample.ramTotalBytes)")
        print("swap_usage  : \(sample.swapUsedBytes) / \(sample.swapTotalBytes)")
        print(String(format: "temp        : cpu %.2f, gpu %.2f (Quelle %@)",
                     sample.cpuTemperature, sample.gpuTemperature,
                     probe.smc.hasTemperatureKeys ? "SMC" : "IOHID"))
        print("fans        : \(sample.fanRPM)")

        if CommandLine.arguments.contains("--channels") {
            print("\n-- IOReport-Kanäle --")
            probe.ioreport.channelDiagnostics().forEach { print("  \($0)") }
            print("\n-- Temperatursensoren (IOHID) --")
            for sensor in probe.temperature.readSensors().sorted(by: { $0.name < $1.name }) {
                print(String(format: "  %@ = %.1f \u{00B0}C", sensor.name, sensor.celsius))
            }
        }
        exit(0)
    }

    private static func mhzList(_ values: [Double]) -> String {
        values.isEmpty ? "n/v" : values.map { String(Int($0)) }.joined(separator: " ")
    }
}
