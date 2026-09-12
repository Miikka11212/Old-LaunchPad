import Foundation
import TrackpadBridge

@main struct TrackpadCallbackChecks {
    @MainActor static func main() async {
        let monitor = TrackpadPinchMonitor(onPinch: { preconditionFailure("A stopped monitor must ignore input") }, onStatus: { _ in })
        let address = UInt(bitPattern: Unmanaged.passUnretained(monitor).toOpaque())
        await Task.detached {
            precondition(!Thread.isMainThread)
            let callback: OLPContactCallback = receiveTrackpadContacts
            for index in 0..<100 {
                let frame = [OLPContact(identifier: 1, x: 0.2, y: 0.3)]
                frame.withUnsafeBufferPointer {
                    callback($0.baseAddress, 1, Double(index) / 120, UnsafeMutableRawPointer(bitPattern: address))
                }
            }
        }.value
        try? await Task.sleep(for: .milliseconds(100))
        withExtendedLifetime(monitor) {}
        print("Passed C trackpad callback execution from a background thread with Swift 6 actor checks enabled.")
    }
}
