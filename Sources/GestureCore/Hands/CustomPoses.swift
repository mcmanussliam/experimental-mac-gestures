import Foundation

/// User-recorded poses, matched by k-nearest-neighbours over canonical landmarks.
public struct CustomPoseSample: Codable, Sendable {
    public var name: String
    public var vector: [Double]
    public init(name: String, vector: [Double]) { self.name = name; self.vector = vector }
}

public struct CustomPoseLibrary: Codable, Sendable {
    public var samples: [CustomPoseSample] = []
    public init(samples: [CustomPoseSample] = []) { self.samples = samples }

    public var names: [String] { Array(Set(samples.map(\.name))).sorted() }

    /// k-NN with majority vote; rejects when the nearest neighbours are too far.
    /// Distance is the *largest* per-joint displacement (in palms): a single finger in a
    /// different state is a different pose, which an averaged metric would blur away.
    public func classify(_ v: [Double], k: Int = 5, threshold: Double) -> (name: String, distance: Double)? {
        guard !samples.isEmpty, !v.isEmpty, v.count.isMultiple(of: 2),
              v.allSatisfy(\.isFinite), k > 0, threshold.isFinite, threshold > 0 else { return nil }
        var dists: [(Double, String)] = samples.compactMap { s in
            guard s.vector.count == v.count, s.vector.allSatisfy(\.isFinite) else { return nil }
            var worst = 0.0
            for j in stride(from: 0, to: v.count - 1, by: 2) {
                let dx = s.vector[j] - v[j], dy = s.vector[j + 1] - v[j + 1]
                worst = max(worst, dx * dx + dy * dy)
            }
            return (worst.squareRoot(), s.name)
        }
        dists.sort { $0.0 < $1.0 }
        let top = dists.prefix(k).filter { $0.0 < threshold }
        guard !top.isEmpty else { return nil }
        var votes: [String: (Int, Double)] = [:]
        for (d, n) in top { let cur = votes[n] ?? (0, .infinity); votes[n] = (cur.0 + 1, min(cur.1, d)) }
        let best = votes.max { a, b in a.value.0 != b.value.0 ? a.value.0 < b.value.0 : a.value.1 > b.value.1 }!
        guard best.value.0 * 2 > top.count else { return nil }
        return (best.key, best.value.1)
    }
}
