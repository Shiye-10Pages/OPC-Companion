import AppKit

class TestAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("applicationDidFinishLaunching called")

        let button = NSStatusBar.system.statusItem(withLength: NSStatusBar.variableLength).button
        print("StatusItem created: \(button != nil)")
    }
}

print("Starting...")

let app = NSApplication.shared
print("App created")

let delegate = TestAppDelegate()
app.delegate = delegate
print("Delegate set")

app.run()
print("Done")
