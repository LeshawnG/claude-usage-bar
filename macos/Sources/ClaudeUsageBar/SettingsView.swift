import SwiftUI
import ServiceManagement

struct SettingsWindowContent: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater

    var body: some View {
        TabView {
            settingsTab("General", systemImage: "gearshape") {
                LaunchAtLoginToggle()

                Picker("Polling Interval", selection: Binding(
                    get: { service.pollingMinutes },
                    set: { service.updatePollingInterval($0) }
                )) {
                    ForEach(UsageService.pollingOptions, id: \.self) { mins in
                        Text(pollingOptionLabel(for: mins))
                            .tag(mins)
                    }
                }

                Toggle("Refresh when opened", isOn: Binding(
                    get: { service.refreshesOnOpen },
                    set: { service.setRefreshesOnOpen($0) }
                ))
                .help("Updates when you open the popover if the last update is 2 or more minutes old.")
            }

            settingsTab("Menu Bar", systemImage: "menubar.rectangle") {
                Toggle("Show percentages", isOn: Binding(
                    get: { service.showsMenuBarPercentages },
                    set: { service.setShowsMenuBarPercentages($0) }
                ))
                Toggle("Show time marker", isOn: Binding(
                    get: { service.showsTimeMarkers },
                    set: { service.setShowsTimeMarkers($0) }
                ))
                .help("A gap on each bar marks how far through the window you are. 5h and 7d turn orange when you're using faster than that.")
                Toggle("Color bars at 60% and 80%", isOn: Binding(
                    get: { service.usesWarningColors },
                    set: { service.setUsesWarningColors($0) }
                ))
            }

            settingsTab("Popover", systemImage: "macwindow") {
                Toggle("Show pace on the 5-hour and 7-day bars", isOn: Binding(
                    get: { service.showsPopoverPace },
                    set: { service.setShowsPopoverPace($0) }
                ))
                .help("Marks how far through each window you are, shades allowance not yet used, and says whether you're over or under pace.")
            }

            settingsTab("Notifications", systemImage: "bell") {
                if !notificationService.isAvailable {
                    Text(notificationsUnavailableMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Group {
                    if service.hasFiveHourWindow {
                        ThresholdSlider(
                            label: "5-hour window",
                            value: notificationService.threshold5h,
                            onChange: { notificationService.setThreshold5h($0) }
                        )
                    }
                    ThresholdSlider(
                        label: "7-day window",
                        value: notificationService.threshold7d,
                        onChange: { notificationService.setThreshold7d($0) }
                    )
                    ThresholdSlider(
                        label: "Extra usage",
                        value: notificationService.thresholdExtra,
                        onChange: { notificationService.setThresholdExtra($0) }
                    )
                }
                .disabled(!notificationService.isAvailable)
            }

            settingsTab("Account", systemImage: "person.crop.circle") {
                if service.isAuthenticated {
                    AccountSection(service: service)
                } else {
                    Text("Not signed in. Sign in from the menu bar.")
                        .foregroundStyle(.secondary)
                }
            }

            settingsTab("Updates", systemImage: "arrow.triangle.2.circlepath") {
                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
                        .textSelection(.enabled)
                }

                if appUpdater.isConfigured {
                    Toggle("Check daily for updates", isOn: Binding(
                        get: { appUpdater.automaticallyChecksForUpdates },
                        set: { appUpdater.setAutomaticallyChecksForUpdates($0) }
                    ))

                    Button("Check for Updates…") {
                        appUpdater.checkForUpdates()
                    }
                    .disabled(!appUpdater.canCheckForUpdates)

                    if let error = appUpdater.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("This build has no update feed, so it cannot check for updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            focusSettingsWindow()
        }
    }

    private func settingsTab<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .tabItem { Label(title, systemImage: systemImage) }
    }
}

private struct AccountSection: View {
    @ObservedObject var service: UsageService

    var body: some View {
        Section("Account") {
            if service.accounts.count > 1 {
                Picker("Show usage for", selection: Binding(
                    get: { service.accounts.first?.id },
                    set: { if let id = $0 { service.switchAccount(to: id) } }
                )) {
                    ForEach(service.accounts.sorted { label(for: $0) < label(for: $1) }) { account in
                        Text(label(for: account)).tag(Optional(account.id))
                    }
                }
            } else if let email = service.accountEmail {
                Text(email)
            }

            if let error = service.lastError {
                ErrorLabel(message: error)
            }

            if service.isAwaitingCode {
                if service.isWaitingForBrowser {
                    BrowserSignInView(service: service)
                } else {
                    CodeEntryView(service: service)
                }
                Text("To add a different account, sign in to it on claude.ai first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Add Account…") {
                        Task { await service.startOAuthFlow() }
                    }
                    Button("Sign Out") {
                        service.signOut()
                    }
                }
            }
        }
    }

    /// Adds the organization when one login is signed in to several.
    private func label(for account: StoredAccount) -> String {
        let email = account.email ?? "Unknown account"
        guard service.accounts.filter({ $0.email == account.email }).count > 1,
              let organization = account.organizationName else {
            return email
        }
        return "\(email) — \(organization)"
    }
}

/// SwiftUI orders Settings front only within this app, and a menu bar app isn't
/// frontmost, so an already-open Settings window would stay behind other apps.
@MainActor
func focusSettingsWindow() {
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        // Settings is the only titled window; the popover and status item aren't.
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}

struct LaunchAtLoginToggle: View {
    @StateObject private var model: LaunchAtLoginModel

    init(bundleURL: URL = Bundle.main.bundleURL) {
        _model = StateObject(
            wrappedValue: LaunchAtLoginModel(bundleURL: bundleURL)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at Login", isOn: Binding(
                get: { model.isEnabled },
                set: { model.setEnabled($0) }
            ))
            .disabled(!model.isSupported)

            if let message = model.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isSupported: Bool
    @Published private(set) var message: String?

    init(bundleURL: URL = Bundle.main.bundleURL) {
        isSupported = supportsLaunchAtLoginManagement(appURL: bundleURL)

        guard isSupported else {
            message = "Install the app in Applications to manage launch at login."
            return
        }

        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = enabled
            message = nil
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
            message = "Could not update launch at login."
        }
    }
}

func supportsLaunchAtLoginManagement(
    appURL: URL = Bundle.main.bundleURL,
    installDirectories: [URL] = launchAtLoginInstallDirectories()
) -> Bool {
    let normalizedAppURL = appURL.resolvingSymlinksInPath().standardizedFileURL

    return installDirectories.contains { directory in
        let normalizedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let directoryPath = normalizedDirectory.path
        let appPath = normalizedAppURL.path

        return appPath == directoryPath || appPath.hasPrefix(directoryPath + "/")
    }
}

func launchAtLoginInstallDirectories(fileManager: FileManager = .default) -> [URL] {
    [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
    ]
}

private struct ThresholdSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        LabeledContent {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: 0...100,
                step: 5
            )
        } label: {
            Text(label)
            Text(value > 0 ? "\(value)%" : "Off")
                .foregroundStyle(.secondary)
        }
        .alignmentGuide(.firstTextBaseline) { d in
            d[VerticalAlignment.center]
        }
    }
}
