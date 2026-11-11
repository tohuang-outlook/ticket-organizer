import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var reopenMainWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let minimized = sender.windows.first(where: { $0.isMiniaturized && $0.canBecomeKey }) {
            minimized.deminiaturize(nil)
            minimized.makeKeyAndOrderFront(nil)
        } else {
            reopenMainWindow?()
        }
        sender.activate(ignoringOtherApps: true)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard sender.windows.contains(where: \.isDocumentEdited) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit without saving?"
        alert.informativeText = "One or more ticket editors have unsaved changes. Keep editing to save them, or discard them and quit."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard and Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
