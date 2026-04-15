import AppKit

print("Starting...")
let app = NSApplication.shared
print("App created")

let delegate = NSApplicationDelegateTest()
app.delegate = delegate

print("Delegate set")
app.run()
print("Done")

class NSApplicationDelegateTest: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("applicationDidFinishLaunching called")
    }
}
