import AppKit
import Darwin
import Testing

/// Host AppKit tests in an application event loop, without launching Mudsnote
/// or initializing its real NoteStore. The test bundle provides fixture stores.
@main
struct MacOSTestRunner {
    @MainActor
    static func main() {
        guard let flag = CommandLine.arguments.firstIndex(of: "--test-bundle-path"),
              CommandLine.arguments.indices.contains(flag + 1),
              dlopen(CommandLine.arguments[flag + 1], RTLD_NOW | RTLD_GLOBAL) != nil else {
            fatalError("Unable to load the test bundle: \(dlerror().map { String(cString: $0) } ?? "missing bundle path")")
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { await Testing.__swiftPMEntryPoint() as Never }
        app.run()
        fatalError("AppKit stopped before Swift Testing completed")
    }
}
