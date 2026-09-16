import AppKit

// Run in isolation with other Hidden Bar instances stopped. Uses disposable,
// unnamed status items and never touches the user's saved layout preferences.
// --legacy-hide reproduces the macOS 27 remove/reinsert ordering failure.
@main
final class SpacerOrderIntegration: NSObject, NSApplicationDelegate {
    private var items: [NSStatusItem] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = SpacerOrderIntegration()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for index in 0..<8 {
            let item = NSStatusBar.system.statusItem(withLength: 20)
            item.button?.title = index == 0 ? "R" : (index == 7 ? "L" : "")
            items.append(item)
        }
        afterLayout {
            guard self.isInRegistrationOrder else {
                print("INCONCLUSIVE: initial items are not laid out in order")
                exit(2)
            }
            for item in self.items[1...6] {
                if CommandLine.arguments.contains("--legacy-hide") { item.isVisible = false }
                item.length = 0
            }
            self.afterLayout {
                for item in self.items[1...6] {
                    if !item.isVisible { item.isVisible = true }
                    item.length = 20
                }
                self.afterLayout {
                    let preserved = self.isInRegistrationOrder
                    print(preserved ? "PASS: zero-width expansion preserves slot order" : "FAIL: expansion reordered slots")
                    exit(preserved ? 0 : 1)
                }
            }
        }
    }

    private var isInRegistrationOrder: Bool {
        let edges = items.compactMap { $0.button?.window?.frame.maxX }
        guard edges.count == items.count else { return false }
        return zip(edges, edges.dropFirst()).allSatisfy { $0 > $1 }
    }

    private func afterLayout(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: action)
    }
}
