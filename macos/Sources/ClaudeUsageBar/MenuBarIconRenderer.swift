import AppKit

private let labelWidth: CGFloat = 14
private let barWidth: CGFloat = 24
private let barHeight: CGFloat = 5
private let rowGap: CGFloat = 3
private let labelGap: CGFloat = 2
private let cornerRadius: CGFloat = 2
private let logoSize: CGFloat = 12
private let logoGap: CGFloat = 2
private let barsWidth: CGFloat = labelWidth + labelGap + barWidth + 2
private let iconWidth: CGFloat = logoSize + logoGap + barsWidth
private let iconHeight: CGFloat = 18
private let fontSize: CGFloat = 8
private let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)

private let pctFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

// Room for two digits; the icon widens only while a window is at 100% or more.
private let pctWidth: CGFloat = ceil(pctText(0.99, ink: .black).size().width)

private func text(_ string: String, ink: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: ink])
}

/// Digits blur sooner than the 5h/7d labels at this size, so they're semibold with 1.5pt before the "%".
private func pctText(_ pct: Double, ink: NSColor) -> NSAttributedString {
    let string = "\(Int(round(pct * 100)))%"
    let text = NSMutableAttributedString(string: string, attributes: [.font: pctFont, .foregroundColor: ink])
    text.addAttribute(.kern, value: 1.5, range: NSRange(location: string.count - 2, length: 1))
    return text
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

private func drawRow(label: String, barX: CGFloat, barY: CGFloat, labelX: CGFloat, ink: NSColor, pct: Double?, pctRightEdge: CGFloat, drawBarFill: (CGFloat, CGFloat) -> Void) {
    let labelText = text(label, ink: ink)
    let labelSize = labelText.size()
    labelText.draw(at: NSPoint(x: labelX + labelWidth - labelSize.width, y: barY + (barHeight - labelSize.height) / 2))
    drawBarFill(barX, barY)
    if let pct {
        let pctLabel = pctText(pct, ink: ink)
        let size = pctLabel.size()
        pctLabel.draw(at: NSPoint(x: pctRightEdge - size.width, y: barY + (barHeight - size.height) / 2))
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
    let shown = [pct5h, pct7d].compactMap { $0 }
    let pctColumn = showsPercentages
        ? shown.map { ceil(pctText($0, ink: .black).size().width) }.reduce(pctWidth, max)
        : 0
    let width = iconWidth + pctColumn
    let isColored = usesWarningColors && shown.contains { warningColor(for: $0) != nil }

    let image = NSImage(size: NSSize(width: width, height: iconHeight), flipped: true) { _ in
        let ink = isColored ? menuBarInk() : .black
        let offset = logoSize + logoGap
        let barX = offset + labelWidth + labelGap
        let topY = (iconHeight - barHeight * 2 - rowGap) / 2
        let bottomY = pct5h == nil ? (iconHeight - barHeight) / 2 : topY + barHeight + rowGap

        drawClaudeLogo(x: 0, y: (iconHeight - logoSize) / 2, size: logoSize, ink: ink)

        let rows: [(String, Double?, Double?, CGFloat)] = [("5h", pct5h, marker5h, topY), ("7d", pct7d, marker7d, bottomY)]
        for (label, pct, marker, y) in rows {
            guard let pct else { continue }
            let fill = usesWarningColors ? warningColor(for: pct) ?? ink : ink
            drawRow(label: label, barX: barX, barY: y, labelX: offset, ink: ink, pct: showsPercentages ? pct : nil, pctRightEdge: width) { x, y in
                drawBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius, pct: pct, ink: ink, fill: fill, marker: marker)
            }
        }
        return true
    }
    image.isTemplate = !isColored
    return image
}

func renderUnauthenticatedIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: iconWidth, height: iconHeight), flipped: true) { _ in
        let offset = logoSize + logoGap
        let barX = offset + labelWidth + labelGap
        let topY = (iconHeight - barHeight * 2 - rowGap) / 2
        let bottomY = topY + barHeight + rowGap

        drawClaudeLogo(x: 0, y: (iconHeight - logoSize) / 2, size: logoSize, ink: .black)

        for (label, y) in [("5h", topY), ("7d", bottomY)] {
            drawRow(label: label, barX: barX, barY: y, labelX: offset, ink: .black, pct: nil, pctRightEdge: iconWidth) { x, y in
                drawDashedBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius)
            }
        }
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - Bar drawing

private func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat, pct: Double, ink: NSColor, fill: NSColor, marker: Double?) {
    let bgRect = NSRect(x: x, y: y, width: width, height: height)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    ink.withAlphaComponent(0.25).setFill()
    bgPath.fill()

    let clampedPct = max(0, min(1, pct))
    if clampedPct > 0 {
        let fillWidth = width * clampedPct
        let fillRect = NSRect(x: x, y: y, width: fillWidth, height: height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        fill.setFill()
        fillPath.fill()
    }

    if let marker {
        NSRect(x: x + width * marker - 0.5, y: y - 1, width: 1, height: height + 2).fill(using: .clear)
    }
}

private func drawDashedBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat) {
    let rect = NSRect(x: x, y: y, width: width, height: height)
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
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

private func drawClaudeLogo(x: CGFloat, y: CGFloat, size: CGFloat, ink: NSColor) {
    guard let logo = claudeLogoImage else { return }
    let rect = NSRect(x: x, y: y, width: size, height: size)
    logo.draw(in: rect)
    if ink != .black {
        ink.setFill()
        rect.fill(using: .sourceAtop)
    }
}
