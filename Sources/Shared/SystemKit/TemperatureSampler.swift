import Foundation

// Liest Temperatursensoren über IOHID (Apple-Vendor-Sensoren, Usage Page 0xff00,
// Usage 0x0005). Die nötigen IOKit-Symbole sind nicht öffentlich deklariert,
// deshalb per dlopen/dlsym aus dem IOKit-Framework. Ohne Root, ohne Rechte.
final class TemperatureSampler {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (UnsafeRawPointer?, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (UnsafeRawPointer?) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer?, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer?, Int64, Int64, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (UnsafeRawPointer?, Int32) -> Double

    private var createClient: CreateFn?
    private var setMatching: SetMatchingFn?
    private var copyServices: CopyServicesFn?
    private var copyProperty: CopyPropertyFn?
    private var copyEvent: CopyEventFn?
    private var getFloat: GetFloatFn?

    private var client: AnyObject?
    private(set) var available = false

    // kIOHIDEventTypeTemperature = 15; das Feld ist (Typ << 16).
    private let temperatureType: Int64 = 15
    private var temperatureField: Int32 { Int32(temperatureType << 16) }

    func start() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            return
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        createClient = sym("IOHIDEventSystemClientCreate", CreateFn.self)
        setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatchingFn.self)
        copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServicesFn.self)
        copyProperty = sym("IOHIDServiceClientCopyProperty", CopyPropertyFn.self)
        copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEventFn.self)
        getFloat = sym("IOHIDEventGetFloatValue", GetFloatFn.self)

        guard let createClient, let setMatching,
              let instance = createClient(kCFAllocatorDefault)?.takeRetainedValue() else {
            return
        }
        client = instance
        let matching: CFDictionary = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x0005] as CFDictionary
        setMatching(pointer(to: instance), matching)
        available = true
    }

    // Alle Sensoren mit Name und Grad Celsius - für Diagnose und Auswahl.
    func readSensors() -> [(name: String, celsius: Double)] {
        guard available, let client, let copyServices, let copyEvent, let getFloat,
              let services = copyServices(pointer(to: client))?.takeRetainedValue() as? [AnyObject] else {
            return []
        }
        var result: [(String, Double)] = []
        for service in services {
            let servicePointer = pointer(to: service)
            guard let event = copyEvent(servicePointer, temperatureType, 0, 0)?.takeRetainedValue() else {
                continue
            }
            let value = getFloat(pointer(to: event), temperatureField)
            guard value > 0, value < 130 else { continue }
            let name = (copyProperty?(servicePointer, "Product" as CFString)?.takeRetainedValue() as? String) ?? "?"
            result.append((name, value))
        }
        return result
    }

    // Repräsentative CPU-/SoC-Temperatur als Mittel der passenden Sensoren.
    func sample() -> Double? {
        // Kalibrierungssensoren ("tcal") sind keine echte Temperatur - ausschließen.
        let sensors = readSensors().filter { !$0.name.lowercased().contains("tcal") }
        guard !sensors.isEmpty else { return nil }
        let dieSensors = sensors.filter { isDieSensor($0.name) }
        let chosen = dieSensors.isEmpty ? sensors : dieSensors
        return chosen.map { $0.celsius }.reduce(0, +) / Double(chosen.count)
    }

    private func isDieSensor(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("die")    // tdie* = Silizium-Die-Sensoren (Apple Silicon)
            || lower.contains("cpu")
            || lower.contains("acc")    // eACC/pACC-Cluster
            || lower.contains("soc")
    }

    private func pointer(to object: AnyObject) -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(object).toOpaque()
    }
}
