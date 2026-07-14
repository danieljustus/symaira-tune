@preconcurrency import AppKit

/// Application delegate for the SymairaTune menu-bar app.
///
/// This is a status-bar-only app (LSUIElement=true) — no dock icon, no main
/// window. All user interaction happens through the menu-bar icon dropdown.
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    /// AppKit's default `@main` entry point (`NSApplicationMain`) only wires up
    /// the delegate when a main nib/storyboard instantiates it. This app has
    /// neither, so without an explicit entry point the delegate is never set
    /// and `applicationDidFinishLaunching` never runs — the app launches but
    /// creates no status item. Set the delegate manually before running.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController = nil
    }
}
