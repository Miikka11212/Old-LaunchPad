import Foundation

@main struct PinchRecognizerChecks {
    static func contacts(scale: Double = 1, dx: Double = 0, count: Int = 4, idOffset: Int32 = 0) -> [PinchContact] {
        let corners = [(0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8), (0.5, 0.2)]
        return corners.prefix(count).enumerated().map { index, p in
            PinchContact(id: Int32(index) + idOffset, x: 0.5 + (p.0 - 0.5) * scale + dx, y: 0.5 + (p.1 - 0.5) * scale)
        }
    }
    static func main() {
        var detector = FourFingerPinchRecognizer()
        precondition(!detector.consume(contacts(), timestamp: 1))
        precondition(!detector.consume(contacts(scale: 0.95), timestamp: 1.04))
        precondition(detector.consume(contacts(scale: 0.7), timestamp: 1.12))
        precondition(!detector.consume(contacts(scale: 0.5), timestamp: 1.2))
        precondition(!detector.consume(contacts(scale: 0.8), timestamp: 3))
        precondition(!detector.consume(contacts(scale: 0.4), timestamp: 3.1), "Pausing with fingers down must not fire twice")
        precondition(!detector.consume([], timestamp: 3.2))
        precondition(!detector.consume(contacts(), timestamp: 3.3))
        precondition(detector.consume(contacts(scale: 0.65), timestamp: 3.4))
        for count in [1, 2, 3, 5] {
            detector = FourFingerPinchRecognizer()
            precondition(!detector.consume(contacts(count: count), timestamp: 1))
            precondition(!detector.consume(contacts(scale: 0.5, count: count), timestamp: 1.1))
        }
        detector = FourFingerPinchRecognizer()
        precondition(!detector.consume(contacts(), timestamp: 1))
        precondition(!detector.consume(contacts(dx: 0.1), timestamp: 1.1), "A swipe is not a pinch")
        precondition(!detector.consume(contacts(scale: 1.2), timestamp: 1.2), "Spreading fingers must not open")
        precondition(!detector.consume(contacts(scale: 0.6, idOffset: 10), timestamp: 1.3), "Changing finger IDs must reset")
        detector = FourFingerPinchRecognizer()
        precondition(!detector.consume(contacts(), timestamp: 1))
        precondition(!detector.consume(contacts(scale: 0.6), timestamp: 2), "Stale frames must start a fresh baseline")
        precondition(!detector.consume(contacts(scale: 0.5), timestamp: .nan))
        detector = FourFingerPinchRecognizer()
        precondition(detector.consumeGesture(contacts(scale: 0.5), timestamp: 1) == nil)
        precondition(detector.consumeGesture(contacts(scale: 0.8), timestamp: 1.12) == .spreadOut)
        precondition(detector.consumeGesture(contacts(scale: 1), timestamp: 1.2) == nil, "Spread fires only once")
        precondition(detector.consumeGesture(contacts(scale: 0.2), timestamp: 1.3) == nil, "Do not open again before fingers lift")
        precondition(detector.consumeGesture([], timestamp: 1.4) == nil)
        precondition(detector.consumeGesture(contacts(), timestamp: 1.5) == nil)
        precondition(detector.consumeGesture(contacts(scale: 0.6), timestamp: 1.62) == .pinchIn)
        for count in [1, 2, 3, 5] {
            detector = FourFingerPinchRecognizer()
            precondition(detector.consumeGesture(contacts(scale: 0.5, count: count), timestamp: 1) == nil)
            precondition(detector.consumeGesture(contacts(count: count), timestamp: 1.12) == nil)
        }
        detector = FourFingerPinchRecognizer()
        precondition(detector.consumeGesture(contacts(scale: 0.5), timestamp: 1) == nil)
        precondition(detector.consumeGesture(contacts(scale: 0.5, dx: 0.1), timestamp: 1.12) == nil)
        print("Passed pinch-in, spread-out, lift-to-rearm, pause debounce, finger count, swipe, ID-change, and stale-frame checks.")
    }
}
