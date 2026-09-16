import AppKit
import Darwin
import Foundation
import Testing

// SwiftPM's async entry point exits when AppKit stops the main run loop after
// dismissing a sheet. Load the same test bundle without calling that entry point;
// Swift Testing still discovers the tests and owns the summary and exit code.
@main
struct MacOSTestRunner {
    static func main() {
        guard let path = ProcessInfo.processInfo.environment["MUDSNOTE_TEST_BUNDLE_PATH"],
              dlopen(path, RTLD_NOW | RTLD_GLOBAL) != nil else {
            let detail = dlerror().map { String(cString: $0) } ?? "Missing test bundle path"
            FileHandle.standardError.write(Data("Cannot load macOS tests: \(detail)\n".utf8))
            exit(1)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        Task {
            await Testing.__swiftPMEntryPoint() as Never
        }
        while true {
            if let event = application.nextEvent(matching: .any, until: .distantFuture, inMode: .default, dequeue: true) {
                application.sendEvent(event)
            }
        }
    }
}
