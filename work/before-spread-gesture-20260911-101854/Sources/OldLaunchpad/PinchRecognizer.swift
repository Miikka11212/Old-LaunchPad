import Foundation

struct PinchContact: Sendable {
    let id: Int32
    let x: Double
    let y: Double
}

/// Recognizes one deliberate four-finger contraction until all fingers lift.
/// Comparing distances from the centroid ignores ordinary swipes and rotation.
struct FourFingerPinchRecognizer {
    private var initial: [Int32: Double] = [:]
    private var initialRadius = 0.0
    private var initialCenter = (x: 0.0, y: 0.0)
    private var beganAt = 0.0
    private var lastTimestamp = -Double.infinity
    private var triggered = false

    mutating func consume(_ contacts: [PinchContact], timestamp: Double) -> Bool {
        guard timestamp.isFinite else { return false }
        if timestamp < lastTimestamp { self = Self() }
        else if timestamp - lastTimestamp > 0.5 { initial = [:] }
        lastTimestamp = timestamp
        if contacts.isEmpty { initial = [:]; triggered = false; return false }
        guard !triggered else { return false }
        guard contacts.count == 4,
              Set(contacts.map(\.id)).count == 4,
              contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            initial = [:]
            return false
        }
        let center = (x: contacts.map(\.x).reduce(0, +) / 4, y: contacts.map(\.y).reduce(0, +) / 4)
        let radii = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, hypot($0.x - center.x, $0.y - center.y)) })
        let radius = radii.values.reduce(0, +) / 4
        if Set(initial.keys) != Set(radii.keys) || timestamp - beganAt > 2 {
            initial = radii
            initialRadius = radius
            initialCenter = center
            beganAt = timestamp
            return false
        }
        guard initialRadius >= 0.09, timestamp - beganAt >= 0.06,
              radius <= initialRadius * 0.76, initialRadius - radius >= 0.04,
              hypot(center.x - initialCenter.x, center.y - initialCenter.y) < 0.16,
              radii.filter({ id, value in value <= initial[id, default: value] * 0.85 }).count >= 3 else { return false }
        triggered = true
        return true
    }
}
