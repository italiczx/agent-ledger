import AgentLedgerCore
import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            DumpCLI.run()
            return
        }
        AgentLedgerApp.main()
    }
}

private final class DumpBox: @unchecked Sendable {
    var text = ""
}

enum DumpCLI {
    static func run() {
        let box = DumpBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            let snapshot = await LedgerService.refresh(range: .week)
            box.text = DumpText.render(snapshot, range: .week)
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 45) == .timedOut {
            fputs("Timed out while reading usage.\n", stderr)
            exit(1)
        }
        print(box.text)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SetupWindow.presentIfNeeded()
    }
}
