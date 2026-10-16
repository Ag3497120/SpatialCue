import Foundation

enum GestureLabel: String, CaseIterable, Identifiable, Codable {
    case pinch, fist, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pinch: return tr("つまむ", "Pinch")
        case .fist: return tr("握る", "Fist")
        case .none: return tr("なし", "None")
        }
    }

    var recordHint: String {
        switch self {
        case .pinch: return tr("親指と人差し指を1秒おきに10回つまむ", "Pinch thumb and index finger 10 times, once a second")
        case .fist: return tr("1秒おきに10回、軽く握って開く", "Make a light fist and open it 10 times, once a second")
        case .none: return tr("10秒ほど、手を開く・指を動かす・腕を普段どおり動かす（ピンチはしない）",
                              "For about 10 seconds, open your hand, move your fingers and arm normally (no pinches)")
        }
    }
}

/// 50 × 6ch の窓から特徴量（36 次元）を作る
enum GestureFeatures {
    static func extract(_ w: [Float]) -> [Double] {
        let ch = PinchDetector.channels
        let n = w.count / ch
        var f: [Double] = []
        f.reserveCapacity(36)
        for c in 0..<ch {
            var sum = 0.0, sq = 0.0, mn = Double.infinity, mx = -Double.infinity, rough = 0.0
            var prev = Double(w[c])
            for k in 0..<n {
                let v = Double(w[k * ch + c])
                sum += v; sq += v * v
                mn = min(mn, v); mx = max(mx, v)
                if k > 0 { rough += abs(v - prev) }
                prev = v
            }
            let mean = sum / Double(n)
            f += [mean, (max(sq / Double(n) - mean * mean, 0)).squareRoot(), mn, mx, rough / Double(n - 1)]
        }
        var jerks: [Double] = []
        var gyroMags: [Double] = []
        for k in 0..<n {
            let g = Vec3(x: Double(w[k * ch + 3]), y: Double(w[k * ch + 4]), z: Double(w[k * ch + 5]))
            gyroMags.append(g.length)
            guard k > 0 else { continue }
            let a = Vec3(x: Double(w[k * ch]), y: Double(w[k * ch + 1]), z: Double(w[k * ch + 2]))
            let p = Vec3(x: Double(w[(k - 1) * ch]), y: Double(w[(k - 1) * ch + 1]), z: Double(w[(k - 1) * ch + 2]))
            jerks.append((a - p).length * 100)
        }
        let mid = jerks.count / 2
        f += [jerks.max() ?? 0, average(jerks), average(Array(jerks[..<mid])), average(Array(jerks[mid...])),
              gyroMags.max() ?? 0, average(gyroMags)]
        return f
    }

    private static func average(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
}

/// 標準化した特徴量での k 近傍法。学習データが少なくても動き、端末上で即座に学習できる。
struct KNNModel {
    let labels: [String]
    let points: [[Double]]
    let mean: [Double]
    let scale: [Double]
    let k: Int
    let rejectDistance: Double
    private(set) var looAccuracy: Double?

    init?(samples: [(label: String, features: [Double])], k: Int = 3) {
        guard samples.count >= 2, let dim = samples.first?.features.count else { return nil }
        let n = Double(samples.count)
        var mean = [Double](repeating: 0, count: dim)
        for s in samples { for d in 0..<dim { mean[d] += s.features[d] / n } }
        var scale = [Double](repeating: 0, count: dim)
        for s in samples { for d in 0..<dim { scale[d] += pow(s.features[d] - mean[d], 2) / n } }
        scale = scale.map { $0 > 1e-12 ? $0.squareRoot() : 1 }

        self.labels = samples.map(\.label)
        self.points = samples.map { s in (0..<dim).map { (s.features[$0] - mean[$0]) / scale[$0] } }
        self.mean = mean
        self.scale = scale
        self.k = k

        // 同じラベル内の最近傍距離の中央値から「どれにも似ていない」と判断する距離を決める
        var nearestSame: [Double] = []
        for i in points.indices {
            var best = Double.infinity
            for j in points.indices where j != i && labels[j] == labels[i] {
                best = min(best, Self.distance(points[i], points[j]))
            }
            if best.isFinite { nearestSame.append(best) }
        }
        nearestSame.sort()
        let median = nearestSame.isEmpty ? 3 : nearestSame[nearestSame.count / 2]
        self.rejectDistance = max(median * 3, 1.5)

        if samples.count >= 4 {
            var correct = 0
            for i in points.indices where vote(points[i], excluding: i)?.label == labels[i] { correct += 1 }
            looAccuracy = Double(correct) / n
        }
    }

    func classify(_ features: [Double]) -> (label: String, confidence: Double)? {
        let x = features.indices.map { (features[$0] - mean[$0]) / scale[$0] }
        return vote(x, excluding: nil)
    }

    private func vote(_ x: [Double], excluding: Int?) -> (label: String, confidence: Double)? {
        var neighbors: [(d: Double, label: String)] = []
        for i in points.indices where i != excluding { neighbors.append((Self.distance(x, points[i]), labels[i])) }
        neighbors.sort { $0.d < $1.d }
        guard let nearest = neighbors.first, nearest.d <= rejectDistance else { return nil }
        var weights: [String: Double] = [:]
        for nb in neighbors.prefix(k) { weights[nb.label, default: 0] += 1 / (nb.d + 1e-3) }
        let total = weights.values.reduce(0, +)
        guard let best = weights.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value / total)
    }

    private static func distance(_ a: [Double], _ b: [Double]) -> Double {
        var s = 0.0
        for i in a.indices { let d = a[i] - b[i]; s += d * d }
        return s.squareRoot()
    }
}
