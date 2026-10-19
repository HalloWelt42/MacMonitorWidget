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
        let cpu = CPUSampler()
        let memory = MemorySampler()
        let gpu = GPUSampler()
        let power = PowerSampler()
        let temperature = TemperatureSampler()
        let smc = SMCSampler()

        _ = cpu.sample()            // Grundlinie
        power.start()               // Energie-Grundlinie
        temperature.start()
        smc.start()
        usleep(500_000)             // halbe Sekunde für ein belastbares Delta
        let cpuReading = cpu.sample()
        let memoryReading = memory.sample()
        let gpuReading = gpu.readUtilization()
        let powerReading = power.sample()

        print("== Leitwarte Dump ==")
        print("CPU gesamt : \(Fmt.percent(cpuReading.total))")
        let cores = cpuReading.perCore.map { Fmt.percentValue($0) }.joined(separator: " ")
        print("CPU/Kern   : \(cores)")
        print("RAM        : \(Fmt.gib(memoryReading.usedBytes)) / \(Fmt.gibWhole(memoryReading.totalBytes)) (\(Fmt.percent(memoryReading.fraction)))")
        if let gpuReading {
            print("GPU        : \(Fmt.percent(gpuReading.value)) via '\(gpuReading.key)'")
        } else {
            print("GPU        : n/v")
        }
        let system = smc.systemPower().map { Fmt.watts($0) } ?? "n/v"
        let pkg = powerReading.package.map { Fmt.watts($0) } ?? "n/v"
        let cpuW = powerReading.cpu.map { Fmt.watts($0) } ?? "n/v"
        let gpuW = powerReading.gpu.map { Fmt.watts($0) } ?? "n/v"
        print("Energie    : System \(system) | Rechen (CPU+GPU+ANE) \(pkg) | CPU \(cpuW) | GPU \(gpuW)")
        let temp = temperature.sample().map { String(format: "%.1f \u{00B0}C", $0) } ?? "n/v"
        print("Temperatur : \(temp)")
        if memoryReading.swapTotalBytes > 0 {
            print("Swap       : \(Fmt.gib(memoryReading.swapUsedBytes)) / \(Fmt.gibWhole(memoryReading.swapTotalBytes)) (\(Fmt.percent(memoryReading.swapFraction)))")
        } else {
            print("Swap       : 0 GB")
        }
        if let fan = smc.fan() {
            let maxText = fan.maxRPM.map { " (max \(Int($0.rounded())))" } ?? ""
            print("Lüfter     : \(Int(fan.rpm.rounded())) U/min\(maxText)")
        } else {
            print("Lüfter     : n/v")
        }
        print("IOReport    : \(power.available ? "verfügbar" : "NICHT verfügbar")")

        print("\n-- Temperatursensoren --")
        let sensors = temperature.readSensors().sorted { $0.celsius > $1.celsius }
        if sensors.isEmpty {
            print("(keine Sensoren lesbar)")
        }
        for sensor in sensors {
            print(String(format: "  %@ = %.1f \u{00B0}C", sensor.name, sensor.celsius))
        }
        if let startError = power.startError {
            print("IOReport-Fehler: \(startError)")
        }

        print("\n-- Energy Model Kanäle --")
        let energyLines = power.energyDiagnostics()
        if energyLines.isEmpty {
            print("(keine Energie-Kanäle lesbar)")
        }
        for line in energyLines {
            print("  \(line)")
        }

        print("\n-- IOAccelerator PerformanceStatistics --")
        let diagnostics = gpu.diagnostics()
        if diagnostics.isEmpty {
            print("(keine IOAccelerator-Dienste gefunden)")
        }
        for entry in diagnostics {
            print("[\(entry.service)]")
            for key in entry.stats.keys.sorted() {
                print("  \(key) = \(entry.stats[key] ?? "")")
            }
        }

        exit(0)
    }
}
