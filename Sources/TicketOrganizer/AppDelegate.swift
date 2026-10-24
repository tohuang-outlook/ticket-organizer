import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
