import AppKit
import SwiftUI
import WindowKit

/// SO-001: the first launch walkthrough. Shown on first launch and whenever
/// Accessibility is missing; can be run again from Settings.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case accessibility
    case screenRecording
    case stageManager
    case importWindows
}

/// SO-003: how the first desk is built from the windows already open.
enum ImportChoice: Sendable {
    /// One group per app (at most 8), named after the app.
    case byApp
    /// Everything in one group.
    case fresh
}

/// Live state for the walkthrough. Polls permissions once a second so the
/// granted state updates without a relaunch.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published private(set) var accessibility = Permissions.accessibility
    @Published private(set) var screenRecording = Permissions.screenRecording
    /// SO-002: whether Apple's Stage Manager is on. Only re-read while its step is showing.
    @Published private(set) var stageManagerOn = AppleStageManager.isOn
    @Published var stageManagerError = false

    @Published var importChoice: ImportChoice = .byApp
    /// The import step only appears on the first run, so running setup again never replaces your groups.
    let firstRun = !Preferences.shared.onboardingDone

    var onFinish: () -> Void = {}
    private var timer: Timer?

    var steps: [OnboardingStep] {
        firstRun ? OnboardingStep.allCases : OnboardingStep.allCases.filter { $0 != .importWindows }
    }
    var index: Int { steps.firstIndex(of: step) ?? 0 }
    var isLast: Bool { index == steps.count - 1 }

    func startPolling() {
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let ax = Permissions.accessibility
        if ax != accessibility {
            accessibility = ax
            // SO-136: move on by itself once access arrives, after a beat to show "Allowed".
            if ax && step == .accessibility {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(700))
                    guard let self, self.step == .accessibility else { return }
                    self.next()
                }
            }
        }
        if ax { Engine.startIfReady() }
        let sr = Permissions.screenRecording
        if sr != screenRecording {
            screenRecording = sr
            if sr, StageController.shared.isRunning { StageController.shared.captureAll() }
        }
        if step == .stageManager {
            let on = AppleStageManager.isOn
            if on != stageManagerOn { stageManagerOn = on }
        }
    }

    /// SO-136: opens Settings with the drag tile beside it, and comes back here once allowed.
    func allowAccessibility() {
        AccessibilityGuide.shared.show { [weak self] in
            self?.refresh()
            OnboardingWindow.shared.bringToFront()
        }
    }

    /// "Turn it off for me".
    func turnOffStageManager() {
        if AppleStageManager.setEnabled(false) {
            Preferences.shared.stageManagerTurnedOff = true
            stageManagerError = false
        } else {
            stageManagerError = true
        }
        stageManagerOn = AppleStageManager.isOn
    }

    func next() {
        if isLast {
            if step == .importWindows { applyImport() }
            finish()
            return
        }
        step = steps[index + 1]
        refresh()
    }

    func back() {
        guard index > 0 else { return }
        step = steps[index - 1]
    }

    /// Builds the first desk. Without Accessibility the controller is not running yet; it groups
    /// windows by app on its own the first time it starts.
    func applyImport() {
        let controller = StageController.shared
        guard controller.isRunning else { return }
        switch importChoice {
        case .byApp: controller.importWindowsByApp()
        case .fresh: controller.importAsOneGroup()
        }
    }

    func finish() {
        Preferences.shared.onboardingDone = true
        onFinish()
    }
}

/// Owns the walkthrough window. `OnboardingWindow.shared.show()` re-runs it.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()
    private var window: NSWindow?
    private var model: OnboardingModel?

    var isVisible: Bool { window?.isVisible ?? false }

    /// Opens the walkthrough. Starts at the Accessibility step when that is all that is missing.
    func show(from start: OnboardingStep? = nil) {
        if let window, window.isVisible {
            if let start { model?.step = start }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let m = OnboardingModel()
        if let start { m.step = start }
        m.onFinish = { [weak self] in self?.close() }
        m.startPolling()
        let w = makeStageWindow(title: "Welcome to Stage One", size: NSSize(width: 620, height: 560),
                                content: OnboardingView(model: m))
        w.delegate = self
        model = m
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func bringToFront() {
        guard let window, window.isVisible else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stopPolling()
        model = nil
        window = nil
    }
}

// MARK: - Views

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepDots(count: model.steps.count, index: model.index)
                .padding(.bottom, 22)
            Group {
                switch model.step {
                case .welcome: WelcomeStep()
                case .accessibility: AccessibilityStep(granted: model.accessibility) { model.allowAccessibility() }
                case .screenRecording: ScreenRecordingStep(granted: model.screenRecording)
                case .stageManager: StageManagerStep(model: model)
                case .importWindows: ImportStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(model.step)
            .transition(.opacity)
            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 620, height: 560)
        .background(Color(hex: 0xfffdfb))
        .foregroundStyle(Theme.ink)
        .animation(.easeOut(duration: 0.18), value: model.step)
    }

    private var footer: some View {
        HStack {
            if model.index > 0 {
                Button("Back") { model.back() }
                    .buttonStyle(StageButtonStyle(kind: .ghost))
            }
            Spacer()
            if model.step == .accessibility && !model.accessibility {
                Button("Later") { model.finish() }
                    .buttonStyle(StageButtonStyle(kind: .ghost))
                    .help("Stage One cannot move windows until Accessibility is allowed")
            }
            Button(primaryTitle) { model.next() }
                .buttonStyle(StageButtonStyle(kind: .spot))
                .keyboardShortcut(.defaultAction)
                .disabled(model.step == .accessibility && !model.accessibility)
        }
    }

    private var primaryTitle: String {
        switch model.step {
        case .welcome: return "Get started"
        case .screenRecording where !model.screenRecording: return model.isLast ? "Use app icons" : "Skip"
        case .stageManager where model.stageManagerOn: return model.isLast ? "Finish anyway" : "Skip"
        case .importWindows: return model.importChoice == .byApp ? "Group my windows" : "Start fresh"
        default: return model.isLast ? "Done" : "Continue"
        }
    }
}

private struct StepDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.spot : (i < index ? Theme.spot.opacity(0.4) : Theme.ink.opacity(0.12)))
                    .frame(width: i == index ? 22 : 7, height: 7)
            }
            Spacer()
            Text("Step \(index + 1) of \(count)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.ink3)
        }
    }
}

private struct StepHeader: View {
    let title: String
    let lede: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.display(30))
                .tracking(-0.6)
            Text(lede)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                MarkView(size: 30)
                Text("Stage One")
                    .font(Theme.display(38))
                    .tracking(-1)
            }
            Text("Stage Manager's calm look, with the memory it never had. Group your windows, arrange them in one click, and save the whole desk as a scene you can bring back tomorrow, on another monitor, or after a restart.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Bullet(text: "Groups wait in a strip on the edge of your screen. Click one to bring it on stage.")
                Bullet(text: "Windows never slide under the strip, and the strip and Dock can sit on any edge.")
                Bullet(text: "Free and open source. Nothing leaves your Mac.")
            }
            Text("Setup takes about a minute.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink3)
        }
    }
}

private struct Bullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(Theme.spot).frame(width: 6, height: 6).offset(y: -2)
            Text(text)
                .font(.system(size: 13.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AccessibilityStep: View {
    let granted: Bool
    let allow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(title: "Allow Accessibility",
                       lede: "Stage One moves, resizes and hides windows for you. macOS only lets an app do that with Accessibility access.")
            StageCard {
                HStack {
                    Text("Accessibility").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    PermissionPill(granted: granted)
                }
                Text(granted
                     ? "All set. Stage One can arrange your windows now."
                     : "Click Allow, then drag the Stage One tile that appears beside System Settings into the list. This page moves on by itself.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("Allow Accessibility", action: allow)
                        .buttonStyle(StageButtonStyle(kind: .ink))
                }
            }
            Text("Stage One only reads window positions, sizes and titles. Titles stay on your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
        }
    }
}

private struct ScreenRecordingStep: View {
    let granted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(title: "Live previews (optional)",
                       lede: "With Screen Recording access the strip shows small live previews of each group. Without it, Stage One works the same and shows app icon tiles instead.")
            StageCard {
                HStack {
                    Text("Screen Recording").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    PermissionPill(granted: granted, missingText: "Using app icons")
                }
                Text(granted
                     ? "Previews are on. They are drawn on your Mac and never saved or sent anywhere."
                     : "Open System Settings, then turn on Stage One under Privacy & Security › Screen & System Audio Recording. If macOS asks, choose Quit & Reopen.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("Open System Settings") {
                        Permissions.requestScreenRecording()
                        Permissions.openScreenRecordingSettings()
                    }
                    .buttonStyle(StageButtonStyle(kind: .ink))
                }
            }
            Text("You can switch previews off any time in Settings › Strip & Dock.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
        }
    }
}

/// SO-002: Apple's Stage Manager has to be off, because both apps hide and move windows.
private struct StageManagerStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(title: "Turn off Stage Manager",
                       lede: "Apple's Stage Manager and Stage One both hide, move and group windows. With both on, windows jump between them and the strip covers Apple's. Stage One does everything Stage Manager does, so it needs Stage Manager off.")
            StageCard {
                HStack {
                    Text("Apple's Stage Manager").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    PermissionPill(granted: !model.stageManagerOn, grantedText: "Off", missingText: "On")
                }
                Text(model.stageManagerOn
                     ? "Turn it off here, or yourself in System Settings › Desktop & Dock › Stage Manager."
                     : "Stage Manager is off. You can turn it back on any time in Stage One's Settings.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if model.stageManagerOn {
                    HStack(spacing: 8) {
                        Button("Turn it off for me") { model.turnOffStageManager() }
                            .buttonStyle(StageButtonStyle(kind: .ink))
                        Button("I'll do it") { AppleStageManager.openSettings() }
                            .buttonStyle(StageButtonStyle(kind: .ghost))
                    }
                }
                if model.stageManagerError {
                    Text("That didn't work. Please turn it off in System Settings instead.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                }
            }
        }
    }
}

/// SO-003: build the first desk from the windows that are already open.
private struct ImportStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Set up your groups",
                       lede: "Stage One can sort the windows you have open right now into groups. You can drag windows between groups, rename them and add more later.")
            ChoiceCard(title: "Group by app (recommended)",
                       detail: byAppDetail,
                       selected: model.importChoice == .byApp) { model.importChoice = .byApp }
            ChoiceCard(title: "Start fresh",
                       detail: "Put every open window in one group and build your own groups as you go.",
                       selected: model.importChoice == .fresh) { model.importChoice = .fresh }
            if !StageController.shared.isRunning {
                Text("Stage One will group your windows by app as soon as Accessibility is allowed.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
            }
        }
    }

    /// The apps that would become groups, in front-to-back order.
    private var byAppDetail: String {
        var names: [String] = []
        for w in StageController.shared.inventory.windows where !names.contains(w.snapshot.appName) {
            names.append(w.snapshot.appName)
        }
        guard !names.isEmpty else { return "One group per app, up to 8, each named after its app." }
        let shown = names.prefix(8).joined(separator: ", ")
        let extra = names.count > 8 ? ", plus one more group for the other \(names.count - 8) apps" : ""
        return "One group per app, named after it: \(shown)\(extra)."
    }
}

private struct ChoiceCard: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                radio
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var radio: some View {
        ZStack {
            Circle().strokeBorder(selected ? Theme.spot : Theme.ink3, lineWidth: 1.5)
            if selected { Circle().fill(Theme.spot).frame(width: 8, height: 8) }
        }
        .frame(width: 16, height: 16)
        .padding(.top, 2)
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(selected ? Theme.spotSoft.opacity(0.55) : Color.white.opacity(0.85))
            .overlay(shape.strokeBorder(selected ? Theme.spot : Theme.line, lineWidth: selected ? 1.5 : 1))
    }
}
