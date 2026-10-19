import Foundation

// Liest Apple-Silicon-Zähler über das private IOReport-Framework (per dlopen,
// ohne Root-Rechte):
// - "Energy Model": Energie je Baustein -> Leistung in Watt (CPU, GPU, ANE)
// - "CPU Stats / CPU Core Performance States": Verweildauer je Taktstufe und Kern
// - "GPU Stats / GPU Performance States": dasselbe für die GPU
// Aus den Verweildauern ergeben sich mittlerer Takt und Auslastung.
final class IOReportSampler {
    struct Reading {
        var cpuWatts: Double = 0
        var gpuWatts: Double = 0
        var aneWatts: Double = 0
        var eCores: [CoreActivity] = []
        var pCores: [CoreActivity] = []
        var gpu = CoreActivity()

        var computeWatts: Double { cpuWatts + gpuWatts + aneWatts }
    }

    private typealias CopyChannelsFn = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias MergeChannelsFn = @convention(c) (CFMutableDictionary, CFDictionary, CFTypeRef?) -> Void
    private typealias CreateSubscriptionFn = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeMutableRawPointer?
    private typealias CreateSamplesFn = @convention(c) (UnsafeRawPointer?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDeltaFn = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias IterateBlock = @convention(block) (CFDictionary) -> Int32
    private typealias IterateFn = @convention(c) (CFDictionary, IterateBlock) -> Void
    private typealias ChannelStringFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias ChannelIntFn = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias StateCountFn = @convention(c) (CFDictionary) -> Int32
    private typealias StateNameFn = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?

    private var copyChannels: CopyChannelsFn?
    private var mergeChannels: MergeChannelsFn?
    private var createSubscription: CreateSubscriptionFn?
    private var createSamples: CreateSamplesFn?
    private var createSamplesDelta: CreateSamplesDeltaFn?
    private var iterate: IterateFn?
    private var channelName: ChannelStringFn?
    private var channelGroup: ChannelStringFn?
    private var channelSubGroup: ChannelStringFn?
    private var channelUnit: ChannelStringFn?
    private var simpleInteger: ChannelIntFn?
    private var stateCount: StateCountFn?
    private var stateName: StateNameFn?
    private var stateResidency: ChannelIntFn?

    private let chip: ChipInfo
    private var subscription: UnsafeMutableRawPointer?
    private var sampleChannels: CFMutableDictionary?
    private var previousSample: CFDictionary?
    private var previousTime: Date?
    private(set) var available = false
    private(set) var startError: String?

    private static let cpuSubGroup = "CPU Core Performance States"
    private static let gpuSubGroup = "GPU Performance States"

    init(chip: ChipInfo = .empty) {
        self.chip = chip
    }

    func start() {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY) else {
            startError = "dlopen: \(String(cString: dlerror()))"
            return
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        copyChannels = sym("IOReportCopyChannelsInGroup", CopyChannelsFn.self)
        mergeChannels = sym("IOReportMergeChannels", MergeChannelsFn.self)
        createSubscription = sym("IOReportCreateSubscription", CreateSubscriptionFn.self)
        createSamples = sym("IOReportCreateSamples", CreateSamplesFn.self)
        createSamplesDelta = sym("IOReportCreateSamplesDelta", CreateSamplesDeltaFn.self)
        iterate = sym("IOReportIterate", IterateFn.self)
        channelName = sym("IOReportChannelGetChannelName", ChannelStringFn.self)
        channelGroup = sym("IOReportChannelGetGroup", ChannelStringFn.self)
        channelSubGroup = sym("IOReportChannelGetSubGroup", ChannelStringFn.self)
        channelUnit = sym("IOReportChannelGetUnitLabel", ChannelStringFn.self)
        simpleInteger = sym("IOReportSimpleGetIntegerValue", ChannelIntFn.self)
        stateCount = sym("IOReportStateGetCount", StateCountFn.self)
        stateName = sym("IOReportStateGetNameForIndex", StateNameFn.self)
        stateResidency = sym("IOReportStateGetResidency", ChannelIntFn.self)

        let missing = [
            copyChannels == nil ? "IOReportCopyChannelsInGroup" : nil,
            createSubscription == nil ? "IOReportCreateSubscription" : nil,
            createSamples == nil ? "IOReportCreateSamples" : nil,
            createSamplesDelta == nil ? "IOReportCreateSamplesDelta" : nil,
            iterate == nil ? "IOReportIterate" : nil,
            simpleInteger == nil ? "IOReportSimpleGetIntegerValue" : nil
        ].compactMap { $0 }
        guard missing.isEmpty else {
            startError = "Symbole fehlen: \(missing.joined(separator: ", "))"
            return
        }
        guard let copyChannels, let createSubscription, let createSamples else { return }

        guard let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else {
            startError = "IOReportCopyChannelsInGroup lieferte nil"
            return
        }
        // Takt-Residenzen nur, wenn die Taktstufen bekannt sind (sonst nicht auswertbar).
        if let mergeChannels, !chip.pFrequencies.isEmpty {
            for (group, subGroup) in [("CPU Stats", Self.cpuSubGroup), ("GPU Stats", Self.gpuSubGroup)] {
                if let extra = copyChannels(group as CFString, subGroup as CFString, 0, 0, 0)?.takeRetainedValue() {
                    mergeChannels(channels, extra, nil)
                }
            }
        }

        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = createSubscription(nil, channels, &subbed, 0, nil) else {
            startError = "IOReportCreateSubscription lieferte nil"
            return
        }
        subbed?.release()

        subscription = sub
        sampleChannels = channels
        available = true

        // Grundlinie für die erste Differenz.
        previousSample = createSamples(sub, channels, nil)?.takeRetainedValue()
        previousTime = Date()
    }

    // Werte seit dem letzten Aufruf (beim ersten Aufruf seit start()).
    func sample() -> Reading? {
        guard available,
              let createSamples, let createSamplesDelta, let iterate,
              let sub = subscription, let channels = sampleChannels,
              let prev = previousSample, let prevTime = previousTime,
              let current = createSamples(sub, channels, nil)?.takeRetainedValue()
        else { return nil }

        let now = Date()
        let elapsed = now.timeIntervalSince(prevTime)
        previousSample = current
        previousTime = now
        guard elapsed > 0,
              let delta = createSamplesDelta(prev, current, nil)?.takeRetainedValue()
        else { return nil }

        var reading = Reading()
        var eCores: [(key: CoreKey, activity: CoreActivity)] = []
        var pCores: [(key: CoreKey, activity: CoreActivity)] = []

        let block: IterateBlock = { [weak self] channel in
            guard let self else { return 0 }
            let group = self.string(self.channelGroup, channel) ?? ""
            let name = self.string(self.channelName, channel) ?? ""

            if group == "Energy Model" {
                self.addPower(channel, name: name, seconds: elapsed, to: &reading)
                return 0
            }
            let subGroup = self.string(self.channelSubGroup, channel) ?? ""
            if group == "CPU Stats", subGroup == Self.cpuSubGroup, let core = CoreKey(channel: name) {
                let table = core.performance ? self.chip.pFrequencies : self.chip.eFrequencies
                guard let activity = Self.activity(self.residencies(channel), frequencies: table) else { return 0 }
                if core.performance {
                    pCores.append((core, activity))
                } else if activity.usage > 0 {
                    // Abgeschaltete Kerne (dauerhaft DOWN) nicht mitzählen.
                    eCores.append((core, activity))
                }
            } else if group == "GPU Stats", subGroup == Self.gpuSubGroup, name == "GPUPH" {
                // Die erste GPU-Stufe ist "aus" und hat keinen Takt.
                let table = Array(self.chip.gpuFrequencies.dropFirst())
                if let activity = Self.activity(self.residencies(channel), frequencies: table) {
                    reading.gpu = activity
                }
            }
            return 0
        }
        iterate(delta, block)

        reading.eCores = eCores.sorted { $0.key < $1.key }.map(\.activity)
        reading.pCores = pCores.sorted { $0.key < $1.key }.map(\.activity)
        return reading
    }

    // MARK: - Energie

    // Kanal-Auswahl chip-übergreifend ohne Doppelzählung: der aggregierte CPU-Kanal
    // endet auf "CPU Energy" (je Die "DIE_n_CPU Energy" auf Ultra-Chips), die GPU
    // heißt genau "GPU Energy" (der Kanal "GPU" ist viel zu hoch), die Neural Engine
    // beginnt mit "ANE".
    private func addPower(_ channel: CFDictionary, name: String, seconds: Double, to reading: inout Reading) {
        guard let simpleInteger else { return }
        let unit = string(channelUnit, channel) ?? "mJ"
        let watts = Double(simpleInteger(channel, 0)) * Self.unitToJoules(unit) / seconds
        if name.hasSuffix("CPU Energy") {
            reading.cpuWatts += watts
        } else if name == "GPU Energy" {
            reading.gpuWatts += watts
        } else if name.hasPrefix("ANE") {
            reading.aneWatts += watts
        }
    }

    private static func unitToJoules(_ unit: String) -> Double {
        switch unit.trimmingCharacters(in: .whitespaces).lowercased() {
        case "mj": return 1e-3
        case "uj", "\u{00B5}j": return 1e-6
        case "nj": return 1e-9
        case "j": return 1
        default: return 1e-3
        }
    }

    // MARK: - Takt aus Residenzen

    private func residencies(_ channel: CFDictionary) -> [(name: String, ticks: Double)] {
        guard let stateCount, let stateResidency else { return [] }
        return (0..<stateCount(channel)).map { index in
            let name = stateName?(channel, index)?.takeUnretainedValue() as String? ?? "S\(index)"
            return (name, Double(stateResidency(channel, index)))
        }
    }

    // Die ersten Zustände sind Ruhezustände (IDLE/DOWN bei der CPU, OFF bei der GPU),
    // danach folgt je Taktstufe ein Zustand. Mittlerer Takt = nach Verweildauer
    // gewichtetes Mittel der aktiven Stufen; Auslastung = Aktivanteil, bezogen auf
    // den Höchsttakt.
    static func activity(_ states: [(name: String, ticks: Double)], frequencies: [Double]) -> CoreActivity? {
        guard !frequencies.isEmpty, states.count > frequencies.count,
              let offset = states.firstIndex(where: { !["IDLE", "DOWN", "OFF"].contains($0.name) })
        else { return nil }

        let activeTicks = states[offset...].map(\.ticks).reduce(0, +)
        let totalTicks = states.map(\.ticks).reduce(0, +)
        var averageMHz = 0.0
        for (index, mhz) in frequencies.enumerated() where offset + index < states.count {
            let share = activeTicks > 0 ? states[offset + index].ticks / activeTicks : 0
            averageMHz += share * mhz
        }

        let activeRatio = totalTicks > 0 ? activeTicks / totalTicks : 0
        let minMHz = frequencies.first ?? 0
        let maxMHz = frequencies.last ?? 1
        let usage = maxMHz > 0 ? max(averageMHz, minMHz) * activeRatio / maxMHz : 0
        return CoreActivity(mhz: averageMHz.rounded(.down), usage: usage, active: activeRatio)
    }

    // MARK: - Diagnose

    // Alle abonnierten Kanäle mit Gruppe, Untergruppe, Einheit und Rohwert.
    func channelDiagnostics() -> [String] {
        guard available, let createSamples, let iterate,
              let sub = subscription, let channels = sampleChannels,
              let sample = createSamples(sub, channels, nil)?.takeRetainedValue()
        else { return [] }

        var lines: [String] = []
        let block: IterateBlock = { [weak self] channel in
            guard let self else { return 0 }
            let group = self.string(self.channelGroup, channel) ?? "?"
            let subGroup = self.string(self.channelSubGroup, channel) ?? ""
            let name = self.string(self.channelName, channel) ?? "?"
            let unit = self.string(self.channelUnit, channel) ?? ""
            let value = self.simpleInteger?(channel, 0) ?? 0
            lines.append("[\(group) / \(subGroup)] \(name) = \(value) \(unit)")
            return 0
        }
        iterate(sample, block)
        return lines
    }

    private func string(_ fn: ChannelStringFn?, _ channel: CFDictionary) -> String? {
        guard let fn, let value = fn(channel) else { return nil }
        return value.takeUnretainedValue() as String
    }
}

// Kern-Kennung aus Kanalnamen wie "PCPU3", "ECPU0", "MCPU2" (M5+, untere Stufe)
// oder "DIE_1_PCPU0" (Ultra). Sortiert nach Die, dann Kernnummer.
private struct CoreKey: Comparable {
    let performance: Bool
    let die: Int
    let index: Int

    init?(channel: String) {
        let die = Self.dieIndex(channel)
        if let index = Self.number(after: "PCPU", in: channel) {
            self.performance = true
            self.die = die
            self.index = index
        } else if let index = Self.number(after: "ECPU", in: channel) ?? Self.number(after: "MCPU", in: channel) {
            self.performance = false
            self.die = die
            self.index = index
        } else {
            return nil
        }
    }

    static func < (lhs: CoreKey, rhs: CoreKey) -> Bool {
        (lhs.die, lhs.index) < (rhs.die, rhs.index)
    }

    private static func number(after prefix: String, in channel: String) -> Int? {
        guard let range = channel.range(of: prefix) else { return nil }
        let digits = channel[range.upperBound...].prefix { $0.isASCII && $0.isNumber }
        return Int(digits)
    }

    private static func dieIndex(_ channel: String) -> Int {
        guard channel.hasPrefix("DIE_") else { return 0 }
        return Int(channel.dropFirst(4).prefix { $0.isNumber }) ?? 0
    }
}
