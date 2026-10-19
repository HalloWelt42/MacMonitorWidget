import Foundation

// Liest die Energie-Kanäle (Apple Silicon "Energy Model") über das private
// IOReport-Framework - per dlopen, ohne das Framework fest zu linken und ohne
// Root-Rechte. Aus der Energiedifferenz zweier Messungen ergibt sich die Leistung
// in Watt (Joule pro Sekunde).
final class PowerSampler {
    struct Reading {
        var package: Double?
        var cpu: Double?
        var gpu: Double?
    }

    // dlsym-Signaturen der IOReport-Funktionen.
    private typealias CopyChannelsFn = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubscriptionFn = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeMutableRawPointer?
    private typealias CreateSamplesFn = @convention(c) (UnsafeRawPointer?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDeltaFn = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias IterateBlock = @convention(block) (CFDictionary) -> Int32
    private typealias IterateFn = @convention(c) (CFDictionary, IterateBlock) -> Void
    private typealias ChannelStringFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias ChannelIntFn = @convention(c) (CFDictionary, Int32) -> Int64

    private var copyChannels: CopyChannelsFn?
    private var createSubscription: CreateSubscriptionFn?
    private var createSamples: CreateSamplesFn?
    private var createSamplesDelta: CreateSamplesDeltaFn?
    private var iterate: IterateFn?
    private var channelName: ChannelStringFn?
    private var channelGroup: ChannelStringFn?
    private var channelUnit: ChannelStringFn?
    private var simpleInteger: ChannelIntFn?

    private var subscription: UnsafeMutableRawPointer?
    private var sampleChannels: CFMutableDictionary?
    private var previousSample: CFDictionary?
    private var previousTime: Date?
    private(set) var available = false
    private(set) var startError: String?

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
        createSubscription = sym("IOReportCreateSubscription", CreateSubscriptionFn.self)
        createSamples = sym("IOReportCreateSamples", CreateSamplesFn.self)
        createSamplesDelta = sym("IOReportCreateSamplesDelta", CreateSamplesDeltaFn.self)
        iterate = sym("IOReportIterate", IterateFn.self)
        channelName = sym("IOReportChannelGetChannelName", ChannelStringFn.self)
        channelGroup = sym("IOReportChannelGetGroup", ChannelStringFn.self)
        channelUnit = sym("IOReportChannelGetUnitLabel", ChannelStringFn.self)
        simpleInteger = sym("IOReportSimpleGetIntegerValue", ChannelIntFn.self)

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

        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = createSubscription(nil, channels, &subbed, 0, nil) else {
            startError = "IOReportCreateSubscription lieferte nil"
            return
        }

        subscription = sub
        sampleChannels = channels
        available = true

        // Grundlinie für die erste Differenz.
        previousSample = createSamples(sub, channels, nil)?.takeRetainedValue()
        previousTime = Date()
    }

    func sample() -> Reading {
        let empty = Reading(package: nil, cpu: nil, gpu: nil)
        guard available,
              let createSamples, let createSamplesDelta, let iterate,
              let sub = subscription, let channels = sampleChannels,
              let prev = previousSample, let prevTime = previousTime,
              let current = createSamples(sub, channels, nil)?.takeRetainedValue()
        else { return empty }

        let now = Date()
        let elapsed = now.timeIntervalSince(prevTime)
        previousSample = current
        previousTime = now
        guard elapsed > 0,
              let delta = createSamplesDelta(prev, current, nil)?.takeRetainedValue()
        else { return empty }

        var cpuJoules = 0.0
        var gpuJoules = 0.0
        var aneJoules = 0.0

        // Kanal-Auswahl nach Apple-Silicon-Konvention (chip-übergreifend robust):
        // der aggregierte CPU-Kanal heißt "CPU Energy" (je Die "DIE_n_CPU Energy"
        // auf Ultra-Chips), die GPU "GPU Energy", die Neural Engine beginnt mit
        // "ANE". So wird weder doppelt gezählt (es gibt zusätzlich granulare
        // Kanäle wie EACC_CPU) noch der falsche GPU-Kanal "GPU" (viel zu hoch)
        // erwischt.
        let block: IterateBlock = { [weak self] channel in
            guard let self, let simpleInteger = self.simpleInteger else { return 0 }
            let unit = self.string(self.channelUnit, channel) ?? "mJ"
            let joules = Double(simpleInteger(channel, 0)) * Self.unitToJoules(unit)
            let name = self.string(self.channelName, channel) ?? ""
            if name.hasSuffix("CPU Energy") {
                cpuJoules += joules
            } else if name == "GPU Energy" {
                gpuJoules += joules
            } else if name.hasPrefix("ANE") {
                aneJoules += joules
            }
            return 0
        }
        iterate(delta, block)

        let packageJoules = cpuJoules + gpuJoules + aneJoules
        return Reading(
            package: packageJoules / elapsed,
            cpu: cpuJoules / elapsed,
            gpu: gpuJoules / elapsed
        )
    }

    // Diagnose für den Dump-Modus: alle Energie-Kanäle mit Gruppe, Einheit, Rohwert.
    func energyDiagnostics() -> [String] {
        guard available, let createSamples, let iterate,
              let sub = subscription, let channels = sampleChannels,
              let sample = createSamples(sub, channels, nil)?.takeRetainedValue()
        else { return [] }

        var lines: [String] = []
        let block: IterateBlock = { [weak self] channel in
            guard let self else { return 0 }
            let group = self.string(self.channelGroup, channel) ?? "?"
            let name = self.string(self.channelName, channel) ?? "?"
            let unit = self.string(self.channelUnit, channel) ?? "?"
            let value = self.simpleInteger?(channel, 0) ?? 0
            lines.append("[\(group)] \(name) = \(value) \(unit)")
            return 0
        }
        iterate(sample, block)
        return lines
    }

    private func string(_ fn: ChannelStringFn?, _ channel: CFDictionary) -> String? {
        guard let fn, let value = fn(channel) else { return nil }
        return value.takeUnretainedValue() as String
    }

    private static func unitToJoules(_ unit: String) -> Double {
        switch unit.lowercased() {
        case "mj": return 1e-3
        case "uj", "\u{00B5}j": return 1e-6
        case "nj": return 1e-9
        case "j": return 1
        default: return 1e-3
        }
    }
}
