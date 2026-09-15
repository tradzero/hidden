import AppKit

// Only unrelated preferences-window/login integration is stubbed. The status-bar
// controller, preferences, timer and calibrator are the production sources.
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController(window: nil)
}
enum Util {
    static func showPrefWindow() {}
    static func setUpAutoStart(isAutoStart: Bool) {}
}

@main
final class ControllerIntegration: NSObject, NSApplicationDelegate {
    var controller: StatusBarController!
    var separator: NSStatusItem!
    var failures = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = ControllerIntegration()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
        exit(delegate.failures == 0 ? 0 : 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Constant.isUsingLTRLanguage = NSApp.userInterfaceLayoutDirection == .leftToRight
        UserDefaults.standard.register(defaults: [
            UserDefaults.Key.isAutoHide: false,
            UserDefaults.Key.alwaysHiddenSectionEnabled: CommandLine.arguments.contains("--always-hidden"),
            UserDefaults.Key.areSeparatorsHidden: CommandLine.arguments.contains("--always-hidden")
        ])
        controller = StatusBarController()
        for property in Mirror(reflecting: controller!).children {
            if property.label == "btnSeparate" { separator = property.value as? NSStatusItem }
            if property.label == "btnExpandCollapse", let item = property.value as? NSStatusItem {
                item.button?.title = "HB-T"
            }
        }
        later(8) {
            self.check(self.separator.length > 20 && self.separator.length < 1000, "initial calibrated collapse")
            self.controller.expandCollapseIfNeeded()
            self.check(self.separator.length == 20, "expand restores width")
        }
        later(9) { self.controller.expandCollapseIfNeeded() }
        later(9.4) { self.controller.expandCollapseIfNeeded() }
        later(12) {
            self.check(self.separator.length == 20, "expand cancels pending calibration")
            self.controller.expandCollapseIfNeeded()
        }
        later(19) {
            self.check(self.separator.length > 20 && self.separator.length < 1000, "recollapse succeeds")
            self.controller.expandCollapseIfNeeded()
        }
        later(20) {
            self.check(self.separator.length == 20, "final expand")
            print("Integration completed: \(self.failures) failures")
            fflush(stdout)
            if !CommandLine.arguments.contains("--hold") { NSApp.terminate(nil) }
        }
        // Even interactive inspection always cleans up its own status items.
        later(180) { NSApp.terminate(nil) }
    }

    func later(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
    func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL"): \(label) length=\(separator.length)")
        if !condition { failures += 1 }
        fflush(stdout)
    }
}
