// Zeichnet das Programmsymbol (Petrol, Salbeigrün, Terminal-Rahmen mit
// Balkenverlauf) und erzeugt daraus Sources/App/AppIcon.icns.
// Aufruf: swift tools/make_icon.swift
import SwiftUI
import AppKit

let petrolTop = Color(red: 0x00 / 255, green: 0x36 / 255, blue: 0x44 / 255)
let petrolBottom = Color(red: 0x00 / 255, green: 0x22 / 255, blue: 0x2C / 255)
let sage = Color(red: 0x98 / 255, green: 0xB8 / 255, blue: 0x90 / 255)

// Verlauf mit ruhigem Grundrauschen und einer Spitze rechts der Mitte.
let bars: [Double] = [0.22, 0.30, 0.26, 0.34, 0.28, 0.40, 0.33, 0.46, 0.38, 0.52, 0.86, 0.62, 0.44, 0.50, 0.36, 0.42]

struct Icon: View {
    var body: some View {
        Canvas { context, size in
            let unit = size.width / 1024
            // Apple-Raster: Körper 824 x 824 mit 100 Rand, leicht nach oben versetzt
            // für den Schatten darunter.
            let body = CGRect(x: 100 * unit, y: 92 * unit, width: 824 * unit, height: 824 * unit)
            let shape = Path(roundedRect: body, cornerRadius: 186 * unit, style: .continuous)

            context.drawLayer { shadowed in
                shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 18 * unit, x: 0, y: 12 * unit))
                shadowed.fill(shape, with: .linearGradient(Gradient(colors: [petrolTop, petrolBottom]),
                                                           startPoint: CGPoint(x: body.midX, y: body.minY),
                                                           endPoint: CGPoint(x: body.midX, y: body.maxY)))
            }
            context.stroke(shape.strokedPath(StrokeStyle(lineWidth: 3 * unit)).offsetBy(dx: 0, dy: 0),
                           with: .color(.white.opacity(0.07)))

            // Terminal-Rahmen mit Titel-Lücke oben links.
            let frame = body.insetBy(dx: 120 * unit, dy: 150 * unit).offsetBy(dx: 0, dy: 20 * unit)
            let line = 18 * unit
            let radius = 34 * unit
            var border = Path()
            let gapStart = frame.minX + 70 * unit
            let gapEnd = gapStart + 250 * unit
            border.move(to: CGPoint(x: gapEnd + 26 * unit, y: frame.minY))
            border.addLine(to: CGPoint(x: frame.maxX - radius, y: frame.minY))
            border.addArc(tangent1End: CGPoint(x: frame.maxX, y: frame.minY), tangent2End: CGPoint(x: frame.maxX, y: frame.minY + radius), radius: radius)
            border.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - radius))
            border.addArc(tangent1End: CGPoint(x: frame.maxX, y: frame.maxY), tangent2End: CGPoint(x: frame.maxX - radius, y: frame.maxY), radius: radius)
            border.addLine(to: CGPoint(x: frame.minX + radius, y: frame.maxY))
            border.addArc(tangent1End: CGPoint(x: frame.minX, y: frame.maxY), tangent2End: CGPoint(x: frame.minX, y: frame.maxY - radius), radius: radius)
            border.addLine(to: CGPoint(x: frame.minX, y: frame.minY + radius))
            border.addArc(tangent1End: CGPoint(x: frame.minX, y: frame.minY), tangent2End: CGPoint(x: frame.minX + radius, y: frame.minY), radius: radius)
            border.addLine(to: CGPoint(x: gapStart - 26 * unit, y: frame.minY))
            context.stroke(border, with: .color(sage), style: StrokeStyle(lineWidth: line, lineCap: .round))

            // Titel als kräftiger Strich in der Lücke.
            var title = Path()
            title.move(to: CGPoint(x: gapStart + 14 * unit, y: frame.minY))
            title.addLine(to: CGPoint(x: gapEnd - 14 * unit, y: frame.minY))
            context.stroke(title, with: .color(sage), style: StrokeStyle(lineWidth: line * 1.9, lineCap: .round))

            // Balken mit Zeilenfugen, unten bündig.
            let plot = frame.insetBy(dx: 48 * unit, dy: 48 * unit)
            let column = plot.width / CGFloat(bars.count)
            let row = 44 * unit
            context.drawLayer { layer in
                for (index, value) in bars.enumerated() {
                    let height = (CGFloat(value) * plot.height / row).rounded() * row
                    let rect = CGRect(x: plot.minX + CGFloat(index) * column, y: plot.maxY - height,
                                      width: column - 6 * unit, height: height)
                    layer.fill(Path(roundedRect: rect, cornerRadius: 4 * unit), with: .color(sage))
                }
                layer.blendMode = .destinationOut
                var y = plot.maxY - row
                while y > plot.minY {
                    layer.fill(Path(CGRect(x: plot.minX, y: y - 4 * unit, width: plot.width, height: 8 * unit)), with: .color(.black))
                    y -= row
                }
            }
        }
    }
}

@MainActor
func png(size: Int) -> Data {
    let renderer = ImageRenderer(content: Icon().frame(width: CGFloat(size), height: CGFloat(size)))
    renderer.scale = 1
    renderer.isOpaque = false
    guard let image = renderer.cgImage else { fatalError("Rendern fehlgeschlagen") }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    for base in [16, 32, 128, 256, 512] {
        try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
        try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
    try! png(size: 1024).write(to: root.appendingPathComponent("docs/icon.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Sources/App/AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "AppIcon.icns geschrieben" : "iconutil fehlgeschlagen")
