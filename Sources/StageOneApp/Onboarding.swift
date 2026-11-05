import AppKit
import SwiftUI
import WindowKit

/// SO-001: the first launch walkthrough. Shown on first launch and whenever
/// Accessibility is missing; can be run again from Settings.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case accessibility
    case screenRecording
}

/// Live state for the walkthrough. Polls permissions once a second so the
/// granted state updates without a relaunch.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published private(set) var accessibility = Permissions.accessibility
    @Published private(set) var screenRecording = Permissions.screenRecording

    var onFinish: () -> Void = {}
    private var timer: Timer?

    var steps: [OnboardingStep] { OnboardingStep.allCases }
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
        if ax != accessibility { accessibility = ax }
        if ax { Engine.startIfReady() }
        let sr = Permissions.screenRecording
        if sr != screenRecording {
            screenRecording = sr
            if sr, StageController.shared.isRunning { StageController.shared.captureAll() }
        }
    }

    func next() {
        if isLast { finish(); return }
        step = steps[index + 1]
    }

    func back() {
        guard index > 0 else { return }
        step = steps[index - 1]
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
        let w = makeStageWindow(title: "Welcome to Stage One", size: NSSize(width: 620, height: 520),
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
                case .accessibility: AccessibilityStep(granted: model.accessibility)
                case .screenRecording: ScreenRecordingStep(granted: model.screenRecording)
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
        .frame(width: 620, height: 520)
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
                     : "Open System Settings, then turn on Stage One under Privacy & Security › Accessibility. This page updates on its own.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("Open System Settings") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
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
