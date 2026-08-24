import AppKit

let application = NSApplication.shared
let delegate = AppController()
application.delegate = delegate
withExtendedLifetime(delegate) {
    application.run()
}
