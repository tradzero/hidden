import AppKit
import ApplicationServices

// Standalone, disposable status items. Never reads/writes Hidden Bar preferences.
@main
final class MenuBarGeometryProbe: NSObject, NSApplicationDelegate {
    var items: [NSStatusItem] = []
    var index = 0
    let lengths: [CGFloat] = [20, 160, 300, 600, 800, 1000, 1800, 3600, 20]

    static func main() {
        if CommandLine.arguments.contains("--environment") {
            print("screens=\(NSScreen.screens.map { $0.frame }) AX=\(AXIsProcessTrusted()) capture=\(CGPreflightScreenCaptureAccess())")
            return
        }
        let app = NSApplication.shared
        let delegate = MenuBarGeometryProbe()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let decoy = CommandLine.arguments.contains("--decoy")
        for title in decoy ? ["HB-A", "HB-B"] : ["HB-P", "|"] {
            let item = NSStatusBar.system.statusItem(withLength: decoy ? 44 : 36)
            item.button?.title = title
            // No autosave name: no permanent layout/preference changes.
            items.append(item)
        }
        if decoy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { NSApp.terminate(nil) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.probe() }
        }
    }

    func probe() {
        guard index < lengths.count else { NSApp.terminate(nil); return }
        let requested = lengths[index]
        items[1].length = requested
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let arrow = self.items[0].button?.window?.frame ?? .zero
            let separator = self.items[1].button?.window?.frame ?? .zero
            print("probe length=\(requested) arrow=\(arrow) separator=\(separator) relativeEdge=\(separator.maxX - arrow.minX)")
            fflush(stdout)
            self.index += 1
            self.probe()
        }
    }
}
