import AppKit
import Darwin

/// Uses the Dock's own Show Desktop action, without simulating keystrokes or
/// changing the hidden/minimized state of individual applications.
@MainActor
enum SystemDesktop {
    private typealias SendNotification = @convention(c) (CFString, UnsafeRawPointer?) -> Void
    private static let library = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/HIServices", RTLD_LAZY | RTLD_LOCAL)
    private static let send: SendNotification? = {
        guard let library, let symbol = dlsym(library, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol, to: SendNotification.self)
    }()

    static func showDesktop() {
        guard let send else {
            NSLog("OldLaunchpad: the system Show Desktop action is unavailable")
            return
        }
        send("com.apple.showdesktop.awake" as CFString, nil)
    }
}
