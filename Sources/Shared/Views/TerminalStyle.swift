import SwiftUI
import AppKit

// Gestaltungsbausteine im Terminal-Stil: Farben, Schrift, Rahmen mit Titeln in
// der Linie und Balken-Verläufe mit Zeilenfugen.
enum TerminalTheme {
    // Petrol als Grund, Salbeigrün für Linien, Schrift und Balken.
    static let background = Color(red: 0x00 / 255, green: 0x2B / 255, blue: 0x36 / 255)
    static let foreground = Color(red: 0x98 / 255, green: 0xB8 / 255, blue: 0x90 / 255)

    // Deckkraft des Petrol-Grunds im Widget: darunter liegt der halbtransparente
    // Systemhintergrund, so dass der Schreibtisch leicht durchscheint.
    static let widgetTint: Double = 0.6
    // Innenabstand des Widgets zum Rand.
    static let widgetPadding: CGFloat = 10

    static let titleSize: CGFloat = 12
    static let detailSize: CGFloat = 11.5

    private static let fontName = "JetBrainsMono-Regular"
    // Das Widget bringt die Schrift selbst mit (Sandbox); das Programm nutzt die
    // installierte, falls vorhanden. Ohne beide: Systemschrift in Festbreite.
    private static let fontAvailable: Bool = {
        if NSFont(name: fontName, size: 12) == nil,
           let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: fontName, size: 12) != nil
    }()

    static func font(_ size: CGFloat) -> Font {
        fontAvailable ? .custom(fontName, size: size) : .system(size: size, design: .monospaced)
    }
}

// Rahmen mit abgerundeten Ecken; die obere und untere Kante bilden Titelzeilen,
// in denen links und rechts Beschriftungen in der Linie sitzen.
struct TerminalBox<Content: View>: View {
    var left: String
    var right: String = ""
    var bottomRight: Text? = nil
    @ViewBuilder var content: Content

    private let radius: CGFloat = 5
    private var edgeHeight: CGFloat { TerminalTheme.titleSize * 1.4 }

    var body: some View {
        VStack(spacing: 0) {
            EdgeRow(left: Text(left), right: right.isEmpty ? nil : Text(right), radius: radius)
                .frame(height: edgeHeight)
            content
                .padding(.horizontal, 6)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            EdgeRow(left: nil, right: bottomRight, radius: radius)
                .frame(height: bottomRight == nil ? 6 : edgeHeight, alignment: bottomRight == nil ? .bottom : .center)
        }
        .background(
            FrameSides(radius: radius)
                .stroke(TerminalTheme.foreground, lineWidth: 1)
                .padding(.vertical, 0.5)
                .padding(.top, edgeHeight / 2 - 0.5)
                .padding(.bottom, (bottomRight == nil ? 0 : edgeHeight / 2) - 0.5)
        )
    }
}

// Waagrechte Kante zwischen den Eckbögen, unterbrochen von den Beschriftungen.
private struct EdgeRow: View {
    let left: Text?
    let right: Text?
    let radius: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            line.frame(width: 4)
            if let left { label(left).layoutPriority(2) }
            line
            if let right { label(right).layoutPriority(1) }
            line.frame(width: 4)
        }
        .padding(.horizontal, radius)
    }

    private var line: some View {
        Rectangle().fill(TerminalTheme.foreground).frame(height: 1).frame(maxWidth: .infinity)
    }

    private func label(_ text: Text) -> some View {
        text
            .font(TerminalTheme.font(TerminalTheme.titleSize))
            .foregroundStyle(TerminalTheme.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// Seiten und Eckbögen des Rahmens; die waagrechten Kanten liefern die EdgeRows.
private struct FrameSides: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = radius
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY), radius: r)
        path.move(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.minY), radius: r)
        return path
    }
}

// Balken-Verlauf, jüngster Wert rechts. Höhen in Achtelschritten einer Zeile,
// dazwischen Fugen wie bei Blockzeichen im Terminal. Die Fugen werden aus den
// Balken ausgestanzt, damit dort der (halbtransparente) Grund durchscheint.
struct BarSparkline: View {
    let values: [Double]        // älteste zuerst
    var maximum: Double? = nil  // ohne Angabe: größter Wert im sichtbaren Ausschnitt

    static let columnWidth: CGFloat = 4
    static let rowHeight: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            let columns = max(Int(size.width / Self.columnWidth), 1)
            let visible = Array(values.suffix(columns))
            let top = maximum ?? (visible.max() ?? 0)
            guard top > 0 else { return }

            let step = Self.rowHeight / 8
            context.drawLayer { layer in
                for (offset, value) in visible.reversed().enumerated() {
                    let raw = CGFloat(min(max(value / top, 0), 1)) * size.height
                    let height = (raw / step).rounded() * step
                    guard height > 0 else { continue }
                    let x = size.width - CGFloat(offset + 1) * Self.columnWidth
                    layer.fill(Path(CGRect(x: x, y: size.height - height, width: Self.columnWidth, height: height)),
                               with: .color(TerminalTheme.foreground))
                }
                layer.blendMode = .destinationOut
                var y = size.height - Self.rowHeight
                while y > 0 {
                    layer.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black))
                    y -= Self.rowHeight
                }
            }
        }
    }
}
