import AppKit
import TrackpadBridge

// This entry point is called on Apple's multitouch thread, never the main actor.
// Keeping it outside the actor-isolated class prevents Swift 6 from attaching
// a main-executor precondition to a C callback created inside startListening.
nonisolated func receiveTrackpadContacts(_ contacts: UnsafePointer<OLPContact>?, _ count: Int32,
                                         _ timestamp: Double, _ context: UnsafeMutableRawPointer?) {
    guard let context, let contacts, count >= 0, count <= 16 else { return }
    let frame = UnsafeBufferPointer(start: contacts, count: Int(count)).map {
        PinchContact(id: $0.identifier, x: Double($0.x), y: Double($0.y))
    }
    let monitor = Unmanaged<TrackpadPinchMonitor>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor [weak monitor] in monitor?.receive(frame, timestamp: timestamp) }
}

@MainActor
final class TrackpadPinchMonitor {
    private var recognizer = FourFingerPinchRecognizer()
    private var listening = false
    private let onPinch: () -> Void
    private let onSpread: () -> Void
    private let onStatus: (Bool) -> Void
    private var observers: [NSObjectProtocol] = []

    init(onPinch: @escaping () -> Void, onSpread: @escaping () -> Void = {}, onStatus: @escaping (Bool) -> Void) {
        self.onPinch = onPinch
        self.onSpread = onSpread
        self.onStatus = onStatus
    }

    func start() {
        if observers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stopListening() }
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.startListening() }
            })
        }
        startListening()
    }

    func stop() {
        stopListening()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
    }

    private func startListening() {
        guard !listening else { return }
        recognizer = FourFingerPinchRecognizer()
        let status = OLPStartTrackpad(receiveTrackpadContacts, Unmanaged.passUnretained(self).toOpaque())
        listening = status == 0
        onStatus(listening)
        if !listening { NSLog("OldLaunchpad: trackpad listener unavailable (%d)", status) }
    }

    fileprivate func receive(_ contacts: [PinchContact], timestamp: Double) {
        guard listening else { return }
        switch recognizer.consumeGesture(contacts, timestamp: timestamp) {
        case .pinchIn: onPinch()
        case .spreadOut: onSpread()
        case nil: break
        }
    }

    private func stopListening() {
        guard listening else { return }
        OLPStopTrackpad()
        listening = false
        recognizer = FourFingerPinchRecognizer()
        onStatus(false)
    }
}
