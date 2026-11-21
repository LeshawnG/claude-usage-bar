import AppKit

private let barWidth: CGFloat = 24
private let barHeight: CGFloat = 5
private let cornerRadius: CGFloat = 2
private let gap: CGFloat = 2
private let logoSize: CGFloat = 12
private let iconHeight: CGFloat = 20
private let rowPitch: CGFloat = 10
private let fontSize: CGFloat = 9.5
/// Between light (274) and regular (400) on the system font's weight axis.
private let fontWeight: CGFloat = 340

private func menuBarFont(monospacedDigits: Bool) -> NSFont {
    let base = monospacedDigits
        ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        : NSFont.systemFont(ofSize: fontSize, weight: .regular)
    // systemFont(ofSize:weight:) snaps to named weights, so set the 'wght' axis directly.
    let weightAxis = NSNumber(value: 0x7767_6874)
    let descriptor = base.fontDescriptor.addingAttributes([.variation: [weightAxis: fontWeight]])
    return NSFont(descriptor: descriptor, size: fontSize) ?? base
}

private let labelFont = menuBarFont(monospacedDigits: false)
private let pctFont = menuBarFont(monospacedDigits: true)
private let labelWidth: CGFloat = ceil(["5h", "7d"].map { text($0, font: labelFont, ink: .black).size().width }.max() ?? 0)
private let iconWidth: CGFloat = logoSize + gap + labelWidth + gap + barWidth + gap
// Room for two digits; the icon widens only while a window is at 100% or more.
private let pctWidth: CGFloat = ceil(pctText(0.99, ink: .black).size().width)

private func text(_ string: String, font: NSFont, ink: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: ink])
}

private func pctText(_ pct: Double, ink: NSColor) -> NSAttributedString {
    let string = "\(Int(round(pct * 100)))%"
    let attributed = NSMutableAttributedString(attributedString: text(string, font: pctFont, ink: ink))
    attributed.addAttribute(.kern, value: 0.5, range: NSRange(location: string.count - 2, length: 1))
    return attributed
}

/// Whole-point baselines keep glyphs on the pixel grid; fractional ones blur across two pixel rows.
private func baselines(rows: Int) -> [CGFloat] {
    let cap = labelFont.capHeight
    let top = (iconHeight - (CGFloat(rows - 1) * rowPitch + cap)) / 2
    return (0..<rows).map { round(top + cap + CGFloat($0) * rowPitch) }
}

private func warningColor(for pct: Double) -> NSColor? {
    switch UsageLevel(pct) {
    case .normal: return nil
    case .warning: return .systemYellow
    case .critical: return .systemRed
    }
}

/// Template images can't hold color, so a colored icon draws its own black or white to suit the menu bar.
private func menuBarInk() -> NSColor {
    NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
}

private func drawRow(label: String, baseline: CGFloat, ink: NSColor, pct: Double?, pctRightEdge: CGFloat, drawBar: (CGFloat, CGFloat) -> Void) {
    let labelText = text(label, font: labelFont, ink: ink)
    labelText.draw(at: NSPoint(x: round(logoSize + gap + labelWidth - labelText.size().width), y: baseline - labelFont.ascender))
    drawBar(logoSize + gap + labelWidth + gap, round(baseline - labelFont.capHeight / 2 - barHeight / 2))
    if let pct {
        let pctLabel = pctText(pct, ink: ink)
        pctLabel.draw(at: NSPoint(x: round(pctRightEdge - pctLabel.size().width), y: baseline - pctFont.ascender))
    }
}

/// `marker5h`/`marker7d` are the share of each window elapsed, drawn as a notch; nil draws none.
func renderIcon(
    pct5h: Double?,
    pct7d: Double,
    showsPercentages: Bool,
    marker5h: Double? = nil,
    marker7d: Double? = nil,
    usesWarningColors: Bool = false
) -> NSImage {
    let candidates: [(String, Double?, Double?)] = [("5h", pct5h, marker5h), ("7d", pct7d, marker7d)]
    let rows: [(String, Double, Double?)] = candidates.compactMap { label, pct, marker in pct.map { (label, $0, marker) } }
    let pctColumn = showsPercentages
        ? rows.map { ceil(pctText($0.1, ink: .black).size().width) }.reduce(pctWidth, max)
        : 0
    let width = iconWidth + pctColumn
    let isColored = usesWarningColors && rows.contains { warningColor(for: $0.1) != nil }

    let image = NSImage(size: NSSize(width: width, height: iconHeight), flipped: true) { _ in
        let ink = isColored ? menuBarInk() : .black
        drawClaudeLogo(ink: ink)
        for ((label, pct, marker), baseline) in zip(rows, baselines(rows: rows.count)) {
            let fill = usesWarningColors ? warningColor(for: pct) ?? ink : ink
            drawRow(label: label, baseline: baseline, ink: ink, pct: showsPercentages ? pct : nil, pctRightEdge: width) { x, y in
                drawBar(x: x, y: y, pct: pct, ink: ink, fill: fill, marker: marker)
            }
        }
        return true
    }
    image.isTemplate = !isColored
    return image
}

func renderUnauthenticatedIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: iconWidth, height: iconHeight), flipped: true) { _ in
        drawClaudeLogo(ink: .black)
        for (label, baseline) in zip(["5h", "7d"], baselines(rows: 2)) {
            drawRow(label: label, baseline: baseline, ink: .black, pct: nil, pctRightEdge: iconWidth) { x, y in
                drawDashedBar(x: x, y: y)
            }
        }
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - Bar drawing

private func drawBar(x: CGFloat, y: CGFloat, pct: Double, ink: NSColor, fill: NSColor, marker: Double?) {
    ink.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius).fill()

    let clampedPct = max(0, min(1, pct))
    if clampedPct > 0 {
        fill.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth * clampedPct, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    if let marker {
        NSRect(x: (x + barWidth * marker).rounded(.down), y: y - 1, width: 1, height: barHeight + 2).fill(using: .clear)
    }
}

private func drawDashedBar(x: CGFloat, y: CGFloat) {
    let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor.black.withAlphaComponent(0.25).setStroke()
    path.lineWidth = 1
    let dashPattern: [CGFloat] = [2, 2]
    path.setLineDash(dashPattern, count: 2, phase: 0)
    path.stroke()
}

// MARK: - Claude logo (pre-rendered 512px template PNG)

private let claudeLogoImage: NSImage? = {
    if let bundle = claudeUsageBarResourceBundle(),
       let png = bundle.url(forResource: "claude-logo", withExtension: "png") {
        return NSImage(contentsOf: png)
    }
    return nil
}()

private func drawClaudeLogo(ink: NSColor) {
    guard let logo = claudeLogoImage else { return }
    let rect = NSRect(x: 0, y: round((iconHeight - logoSize) / 2), width: logoSize, height: logoSize)
    logo.draw(in: rect)
    if ink != .black {
        ink.setFill()
        rect.fill(using: .sourceAtop)
    }
}
