import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Usage")
                .font(.headline)
            if !service.isAuthenticated {
                signInView
            } else {
                usageView
            }
        }
        .padding()
        .frame(width: 340)
        .background(WindowKeyObserver { service.popoverDidOpen() })
    }

    @ViewBuilder
    private var signInView: some View {
        if service.isWaitingForBrowser {
            BrowserSignInView(service: service)
        } else if service.isAwaitingCode {
            CodeEntryView(service: service)
        } else {
            Text("Sign in to view your usage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task { await service.startOAuthFlow() }
            } label: {
                Text("Sign in with Claude")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }

        if let error = service.lastError {
            ErrorLabel(message: error)
        }

        Divider()
        HStack {
            settingsButton
            Spacer()
            quitButton
        }
    }

    @ViewBuilder
    private var usageView: some View {
        if service.hasFiveHourWindow {
            UsageBucketRow(
                label: "5-Hour Window",
                bucket: service.usage?.fiveHour,
                elapsed: service.showsPopoverPace ? service.progress5h : nil
            )
        }

        UsageBucketRow(
            label: "7-Day Window",
            bucket: service.usage?.sevenDay,
            elapsed: service.showsPopoverPace ? service.progress7d : nil
        )

        let perModel = service.usage?.perModelWeekly ?? []
        if !perModel.isEmpty {
            Divider()
            Text("Per-Model (7 day)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            perModelRows(perModel)
        }

        if let extra = service.usage?.extraUsage, extra.isEnabled {
            Divider()
            ExtraUsageRow(extra: extra)
        }

        Divider()
        UsageChartView(historyService: historyService, showsFiveHour: service.hasFiveHourWindow)

        if let error = service.lastError {
            Divider()
            ErrorLabel(message: error)
        }

        Divider()

        HStack(spacing: 12) {
            if let updated = service.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }

        HStack(spacing: 12) {
            settingsButton
            Spacer()
            Button("Refresh") {
                Task { await service.fetchUsage() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            quitButton
        }
    }

    /// How many per-model rows render inline before the section starts scrolling.
    private static let inlinePerModelRowLimit = 6
    /// Approximate height of one `UsageBucketRow`, used only to size the scroller.
    private static let perModelRowHeight: CGFloat = 52

    /// The number of model-scoped windows the server reports is unbounded, and
    /// the popover has a fixed width and no outer scroll view — so past a
    /// handful of rows this section scrolls instead of pushing the chart and
    /// the controls off-screen.
    @ViewBuilder
    private func perModelRows(_ entries: [PerModelUsage]) -> some View {
        let rows = VStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
                UsageBucketRow(label: entry.displayName, bucket: entry.bucket)
            }
        }

        if entries.count > Self.inlinePerModelRowLimit {
            ScrollView {
                rows
            }
            .frame(height: CGFloat(Self.inlinePerModelRowLimit) * Self.perModelRowHeight)
        } else {
            rows
        }
    }

    private var settingsButton: some View {
        Button("Settings…") {
            openSettings()
            focusSettingsWindow()
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private var quitButton: some View {
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Subviews

struct BrowserSignInView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        Text("Approve access in your browser to finish signing in.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        HStack {
            Button("Cancel") {
                service.endOAuthFlow()
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Paste a code instead") {
                service.switchToPastedCode()
            }
            .buttonStyle(.borderless)
        }
    }
}

struct CodeEntryView: View {
    @ObservedObject var service: UsageService
    @State private var code = ""

    var body: some View {
        Text("Paste the code from your browser:")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        HStack(spacing: 4) {
            TextField("code#state", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { submit() }
            Button {
                if let str = NSPasteboard.general.string(forType: .string) {
                    code = str.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
        }

        HStack {
            Button("Cancel") {
                service.endOAuthFlow()
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Submit") { submit() }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty)
        }
    }

    private func submit() {
        let value = code
        Task { await service.submitOAuthCode(value) }
    }
}

struct ErrorLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .font(.caption)
    }
}

private struct UsageBucketRow: View {
    let label: String
    let bucket: UsageBucket?
    /// Share of the window elapsed; nil hides the pace marker and words.
    var elapsed: Double? = nil

    private var pace: Pace? {
        guard let elapsed, let used = bucket?.utilization else { return nil }
        return Pace(used: used / 100.0, elapsed: elapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(pace?.isOver == true ? Color.orange : Color.primary)
                Spacer()
                Text(percentageText)
                    .font(.subheadline)
                    .monospacedDigit()
            }
            UsageBar(
                value: (bucket?.utilization ?? 0) / 100.0,
                color: colorForPct((bucket?.utilization ?? 0) / 100.0),
                elapsed: pace == nil ? nil : elapsed
            )
            Group {
                if let resetDate = bucket?.resetsAtDate {
                    HStack {
                        Text("Resets \(resetDate, style: .relative)")
                        Spacer()
                        if let pace {
                            Text(pace.label)
                        }
                    }
                } else if bucket?.utilization == 0 {
                    Text("Starts with your next message")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var percentageText: String {
        guard let pct = bucket?.utilization else { return "—" }
        return "\(Int(round(pct)))%"
    }
}

private struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extra Usage")
                .font(.subheadline)
            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                HStack {
                    Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    if let pct = extra.utilization {
                        Text("\(Int(round(pct)))%")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                UsageBar(value: (extra.utilization ?? 0) / 100.0, color: .blue)
            }
        }
    }
}

private func colorForPct(_ pct: Double) -> Color {
    switch UsageLevel(pct) {
    case .normal: return .green
    case .warning: return .yellow
    case .critical: return .red
    }
}

/// Drawn instead of a tinted ProgressView, which can fall back to the system
/// accent color after a light/dark switch. Same 6pt bar in an 18pt row.
/// With `elapsed`, a gap marks now and a lighter band shows allowance not yet used.
private struct UsageBar: View {
    let value: Double
    let color: Color
    var elapsed: Double? = nil

    var body: some View {
        Canvas { context, size in
            context.fill(capsule(width: size.width, height: size.height), with: .style(HierarchicalShapeStyle.quaternary))
            if let elapsed, elapsed > value {
                context.fill(capsule(width: size.width * elapsed, height: size.height), with: .color(.primary.opacity(0.22)))
            }
            context.fill(capsule(width: size.width * min(value, 1), height: size.height), with: .color(color))
            if let elapsed {
                context.blendMode = .clear
                context.fill(Path(CGRect(x: (size.width * elapsed).rounded() - 1, y: 0, width: 2, height: size.height)), with: .color(.black))
            }
        }
        .frame(height: 6)
        .padding(.vertical, 6)
    }

    private func capsule(width: CGFloat, height: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: min(width, height) / 2)
    }
}

/// Calls `action` each time the hosting window becomes key, which for the menu bar
/// popover is every time it opens. Its view stays in the window between opens, so
/// `onAppear` can't be relied on for this.
private struct WindowKeyObserver: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.action = action
    }

    final class ObserverView: NSView {
        var action: () -> Void = {}
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = window.map {
                NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: $0, queue: .main) { [weak self] _ in
                    self?.action()
                }
            }
        }
    }
}

private extension Pace {
    var label: String {
        switch self {
        case .under(let points): return "\(points)% under pace"
        case .on: return "on pace"
        case .over(let points): return "\(points)% over pace"
        }
    }
}
