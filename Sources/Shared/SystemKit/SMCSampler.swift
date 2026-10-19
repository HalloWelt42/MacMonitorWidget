import Foundation
import IOKit

// Liest Werte aus dem System Management Controller (SMC): die Systemleistung
// ("PSTR", Watt) und die Lüfterdrehzahlen. Apple-Silicon, sudolos.
//
// Die SMC-Datenstruktur (KeyData, 80 Byte) wird nicht als Swift-Struct
// nachgebildet, sondern offsetbasiert in einem Rohpuffer beschrieben/gelesen.
// Das macht das exakte C-Speicherlayout unabhängig von Swift-Annahmen.
final class SMCSampler {
    struct FanReading {
        var rpm: Double
        var maxRPM: Double?
    }

    private var connection: io_connect_t = 0
    private(set) var available = false
    private var fanKeys: [String] = []

    private let structSize = 80
    // Offsets in der KeyData-Struktur (#[repr(C)]).
    private let offKey = 0
    private let offDataSize = 28
    private let offDataType = 32
    private let offDataAttributes = 36
    private let offResult = 40
    private let offData8 = 42
    private let offData32 = 44
    private let offBytes = 48

    func start() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var device = IOIteratorNext(iterator)
        while device != 0 {
            var nameBuffer = [CChar](repeating: 0, count: 128)
            let name = IORegistryEntryGetName(device, &nameBuffer) == KERN_SUCCESS ? String(cString: nameBuffer) : ""
            if name == "AppleSMCKeysEndpoint" {
                if IOServiceOpen(device, mach_task_self_, 0, &connection) == KERN_SUCCESS {
                    available = true
                }
                IOObjectRelease(device)
                break
            }
            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }

        // Lüfter-Schlüssel einmalig ermitteln (F<n>Ac) - die Aufzählung ist teuer.
        if available {
            fanKeys = enumerateFanKeys()
        }
    }

    // Gesamte Systemleistung in Watt oder nil.
    func systemPower() -> Double? {
        numeric("PSTR")
    }

    // Durchschnittliche Lüfterdrehzahl (U/min) und höchste gemeldete Maximaldrehzahl.
    func fan() -> (rpm: Double, maxRPM: Double?)? {
        let readings = fans()
        guard !readings.isEmpty else { return nil }
        let average = readings.map(\.rpm).reduce(0, +) / Double(readings.count)
        let maxRPM = readings.compactMap(\.maxRPM).max()
        return (average, maxRPM)
    }

    private func fans() -> [FanReading] {
        fanKeys.compactMap { key in
            guard let rpm = numeric(key) else { return nil }
            let maxKey = String(key.dropLast(2)) + "Mx"   // F0Ac -> F0Mx
            let maxRPM = numeric(maxKey)
            return FanReading(rpm: rpm, maxRPM: (maxRPM ?? 0) > 0 ? maxRPM : nil)
        }
    }

    // MARK: - Schlüssel-Lesen

    // Liefert (Typ-Kürzel, Rohbytes) eines Schlüssels.
    private func readRaw(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard available, key.utf8.count == 4 else { return nil }
        let keyId = fourCC(key)

        var infoInput = [UInt8](repeating: 0, count: structSize)
        putUInt32(&infoInput, offKey, keyId)
        infoInput[offData8] = 9
        guard let infoOutput = call(infoInput) else { return nil }
        let dataSize = Int(getUInt32(infoOutput, offDataSize))
        let dataType = getUInt32(infoOutput, offDataType)
        guard dataSize > 0, dataSize <= 32 else { return nil }

        var valueInput = [UInt8](repeating: 0, count: structSize)
        putUInt32(&valueInput, offKey, keyId)
        putUInt32(&valueInput, offDataSize, UInt32(dataSize))
        putUInt32(&valueInput, offDataType, dataType)
        valueInput[offDataAttributes] = infoOutput[offDataAttributes]
        valueInput[offData8] = 5
        guard let valueOutput = call(valueInput), valueOutput[offResult] == 0 else { return nil }

        let bytes = Array(valueOutput[offBytes ..< (offBytes + dataSize)])
        return (fourCCString(dataType), bytes)
    }

    // Dekodiert einen numerischen Schlüssel je nach SMC-Datentyp.
    private func numeric(_ key: String) -> Double? {
        guard let (type, bytes) = readRaw(key) else { return nil }
        switch type {
        case "flt " where bytes.count == 4:
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "fpe2" where bytes.count >= 2:
            return Double((UInt16(bytes[0]) << 6) | (UInt16(bytes[1]) >> 2))
        case "ui8 " where !bytes.isEmpty:
            return Double(bytes[0])
        case "ui16" where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count >= 4:
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }

    private func keyCount() -> Int {
        guard let (_, bytes) = readRaw("#KEY"), bytes.count >= 4 else { return 0 }
        return Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
    }

    private func keyByIndex(_ index: UInt32) -> String? {
        var input = [UInt8](repeating: 0, count: structSize)
        input[offData8] = 8
        putUInt32(&input, offData32, index)
        guard let output = call(input), output[offResult] == 0 else { return nil }
        let value = getUInt32(output, offKey)
        let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }

    private func enumerateFanKeys() -> [String] {
        let count = keyCount()
        guard count > 0, count < 100_000 else { return [] }
        var keys: [String] = []
        for index in 0..<UInt32(count) {
            guard let key = keyByIndex(index) else { continue }
            if key.count == 4, key.hasPrefix("F"), key.hasSuffix("Ac") {
                keys.append(key)
            }
        }
        return keys.sorted()
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: structSize)
        var outputSize = structSize
        let result = input.withUnsafeBytes { inputPointer in
            output.withUnsafeMutableBytes { outputPointer in
                IOConnectCallStructMethod(
                    connection, 2,
                    inputPointer.baseAddress, structSize,
                    outputPointer.baseAddress, &outputSize
                )
            }
        }
        return result == KERN_SUCCESS ? output : nil
    }

    private func fourCC(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }

    private func fourCCString(_ value: UInt32) -> String {
        let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }

    private func putUInt32(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        buffer[offset] = UInt8(value & 0xFF)
        buffer[offset + 1] = UInt8((value >> 8) & 0xFF)
        buffer[offset + 2] = UInt8((value >> 16) & 0xFF)
        buffer[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func getUInt32(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(buffer[offset])
            | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16)
            | (UInt32(buffer[offset + 3]) << 24)
    }
}
