import AppKit
import Sparkle

/// Keeps Sparkle alive for the life of the process and exposes the two settings
/// the panel needs: check now, and whether to install without asking.
@MainActor
final class UpdateController {
    static let shared = UpdateController()

    private let controller: SPUStandardUpdaterController

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
