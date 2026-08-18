import AppKit
import Darwin

if CommandLine.arguments.contains("--unregister-login-item") {
    do {
        try LoginItemController.setEnabled(false)
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Could not unregister OpenVale as a login item: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    application.delegate = appDelegate
    application.run()
}
