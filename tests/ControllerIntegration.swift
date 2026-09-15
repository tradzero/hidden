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
    var arrow: NSStatusItem!
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
        precondition(Bundle.main.bundleIdentifier == "com.tradzero.hidden.integration")
        UserDefaults.standard.removePersistentDomain(forName: "com.tradzero.hidden.integration")
        UserDefaults.standard.register(defaults: [
            UserDefaults.Key.isAutoHide: false,
            UserDefaults.Key.alwaysHiddenSectionEnabled: CommandLine.arguments.contains("--always-hidden"),
            UserDefaults.Key.areSeparatorsHidden: CommandLine.arguments.contains("--always-hidden")
        ])
        controller = StatusBarController()
        for property in Mirror(reflecting: controller!).children {
            if property.label == "btnSeparate" { separator = property.value as? NSStatusItem }
            if property.label == "btnExpandCollapse", let item = property.value as? NSStatusItem {
                arrow = item
                item.button?.title = "HB-T"
            }
        }
        // Calibration settles asynchronously, especially with two separators.
        // Wait for completion with a deadline instead of sampling an in-flight probe.
        later(1.5) { self.whenSettled {
            self.check(self.separator.length > 20 && self.separator.length < 1000, "initial calibrated collapse")
            self.check(self.spacers("ordinarySpacers").count == 6 && self.spacers("ordinarySpacers").allSatisfy { $0.isVisible && $0.length == self.separator.length }, "ordinary spacers share the calibrated span")
            self.arrow.button?.performClick(nil)
            self.check(self.separator.length == 20, "button activation without mouse-up expands")
            self.check(self.arrow.button?.toolTip == "Hide icons".localized, "expanded action description")
            self.later(0.5) {
                NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                self.later(0.5) {
                    self.controller.expandCollapseIfNeeded()
                    self.later(1) {
                        self.controller.expandCollapseIfNeeded()
                        self.later(2) {
                            self.check(self.separator.length == 20, "expand cancels pending calibration")
                            self.controller.expandCollapseIfNeeded()
                            self.whenSettled {
                                self.check(self.separator.length > 20 && self.separator.length < 1000, "recollapse succeeds")
                                self.controller.expandCollapseIfNeeded()
                                self.whenSettled { self.finish() }
                            }
                        }
                    }
                }
            }
        } }
        // Even interactive inspection always cleans up its own status items.
        later(180) { NSApp.terminate(nil) }
    }

    func whenSettled(deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 30,
                     _ action: @escaping () -> Void) {
        let busy = Mirror(reflecting: controller!).children.first { $0.label == "modernLayoutBusy" }?.value as? Bool
        guard let busy = busy else { fatalError("Missing controller calibration state") }
        if !busy { action(); return }
        if ProcessInfo.processInfo.systemUptime >= deadline {
            check(false, "calibration settled within 30 seconds")
            exit(1)
        }
        later(0.2) { self.whenSettled(deadline: deadline, action) }
    }

    func finish() {
        check(separator.length == 20, "final expand")
        check(spacers("ordinarySpacers").allSatisfy { !$0.isVisible && $0.length == 0 }, "ordinary spacers take no space on expand")
        if CommandLine.arguments.contains("--always-hidden") {
            let property = Mirror(reflecting: controller!).children.first { $0.label == "btnAlwaysHidden" }
            let item = property?.value as? NSStatusItem
            check((item?.length ?? 0) > 20, "always-hidden remains inflated on ordinary expand")
            check(spacers("alwaysSpacers").count == 6 && spacers("alwaysSpacers").allSatisfy { $0.isVisible && $0.length == item?.length }, "always-hidden spacers remain inflated on ordinary expand")
        }
        later(0.4) {
            self.controller.expandCollapseIfNeeded()
            self.whenSettled { self.checkApplicationActivation() }
        }
    }

    func spacers(_ name: String) -> [NSStatusItem] {
        guard let items = Mirror(reflecting: controller!).children.first(where: { $0.label == name })?.value as? [NSStatusItem] else { fatalError("Missing spacer group") }
        return items
    }

    func checkApplicationActivation() {
        let previous = Mirror(reflecting: controller!).children.first { $0.label == "ordinaryCalibration" }?.value as? CollapseLengthCalibrator
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        let cached = Mirror(reflecting: controller!).children.first { $0.label == "ordinaryCachedLength" }?.value as? CGFloat
        check(cached == nil, "application activation discards the accepted old span")
        later(0.5) { self.whenSettled {
            let current = Mirror(reflecting: self.controller!).children.first { $0.label == "ordinaryCalibration" }?.value as? CollapseLengthCalibrator
            self.check(current != nil && current !== previous, "application activation performs fresh calibration")
            self.check(self.separator.length > 20 && self.separator.length < 1000, "application activation preserves collapsed intent")
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
            self.controller.expandCollapseIfNeeded()
            self.later(0.5) { self.whenSettled {
                self.check(self.separator.length == 20, "expand cancels application-change recalibration")
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
                self.later(0.5) { self.whenSettled {
                    self.check(self.separator.length == 20, "application activation preserves expanded intent")
                    self.checkAlwaysSectionToggle()
                } }
            } }
        } }
    }

    func checkAlwaysSectionToggle() {
        guard CommandLine.arguments.contains("--always-hidden") else { complete(); return }
        let original = Mirror(reflecting: controller!).children.first { $0.label == "btnAlwaysHidden" }?.value as? NSStatusItem
        let names = spacers("alwaysSpacers").map { $0.autosaveName }
        Preferences.alwaysHiddenSectionEnabled = false
        whenSettled {
            self.check(original?.isVisible == false, "disabled always-hidden separator is hidden")
            self.check(self.spacers("alwaysSpacers").allSatisfy { !$0.isVisible && $0.length == 0 }, "disabled always-hidden spacers take no space")
            Preferences.alwaysHiddenSectionEnabled = true
            self.whenSettled {
                let restored = Mirror(reflecting: self.controller!).children.first { $0.label == "btnAlwaysHidden" }?.value as? NSStatusItem
                self.check(restored === original && self.spacers("alwaysSpacers").map { $0.autosaveName } == names, "reenabling preserves registered slots")
                self.check(self.spacers("alwaysSpacers").allSatisfy { $0.isVisible && $0.length > 20 }, "reenabling restores always-hidden block")
                self.complete()
            }
        }
    }

    func complete() {
        print("Integration completed: \(failures) failures")
        fflush(stdout)
        if !CommandLine.arguments.contains("--hold") { exit(failures == 0 ? 0 : 1) }
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
