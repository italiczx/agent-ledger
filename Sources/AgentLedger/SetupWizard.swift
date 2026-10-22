import AgentLedgerCore
import AppKit
import SwiftUI

struct SetupWizard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent Ledger")
                    .font(.headline)
                Text(model.setupStep == 0 ? "Step 1 of 2" : "Step 2 of 2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.setupStep == 0 {
                toolsStep
            } else {
                displayStep
            }

            HStack {
                if model.setupStep > 0 {
                    Button("Back") { model.setupStep = 0 }
                }
                Spacer()
                Button(model.setupStep == 0 ? "Continue" : "Start using Agent Ledger") {
                    if model.setupStep == 0 {
                        model.setupStep = 1
                    } else {
                        model.settings.didCompleteSetup = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 368, alignment: .topLeading)
        .onChange(of: model.settings.didCompleteSetup) { _, done in
            if done { SetupWindow.close() }
        }
    }

    private var toolsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which tools should the menu bar watch?")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Turn off a tool you don’t use. You can change this later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Codex", isOn: Bindable(model.settings).showCodex)
            Toggle("Cursor", isOn: Bindable(model.settings).showCursor)
            if !model.settings.showCodex && !model.settings.showCursor {
                Text("With both off, the menu bar says Ledger until you turn one on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var displayStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How should quota appear in the menu bar?")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Picker("Menu bar", selection: Bindable(model.settings).metric) {
                Text("Remaining").tag(MenuMetric.remaining)
                Text("Used").tag(MenuMetric.used)
                Text("Off").tag(MenuMetric.off)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(displayExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Text("Menu bar preview")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var displayExplanation: String {
        switch model.settings.metric {
        case .remaining:
            "Shows the percent still left. Codex is Cx and Cursor is Cu."
        case .used:
            "Shows the percent already used."
        case .off:
            "Keeps the menu bar item, without numbers."
        }
    }

    private var preview: String {
        if model.settings.metric == .off || (!model.settings.showCodex && !model.settings.showCursor) {
            return "Ledger"
        }
        let live = model.menuTitle
        if live != "Ledger" && live != "Ledger …" {
            return live
        }
        var parts: [String] = []
        if model.settings.showCodex {
            parts.append(model.settings.metric == .used ? "Cx 28%" : "Cx 72%")
        }
        if model.settings.showCursor {
            parts.append(model.settings.metric == .used ? "Cu 7%" : "Cu 93%")
        }
        return parts.joined(separator: "  ")
    }
}

@MainActor
enum SetupWindow {
    private static var window: NSWindow?

    static func presentIfNeeded() {
        guard !AppModel.shared.settings.didCompleteSetup else { return }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let host = NSHostingController(rootView: SetupWizard(model: AppModel.shared).padding(20))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "Agent Ledger"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func close() {
        window?.close()
        window = nil
    }
}
