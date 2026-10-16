import Foundation

/// 指をつまむ・握るときに手首へ伝わる小さな衝撃を切り出して分類する。
/// 100Hz の加速度＋ジャイロから、ピークを中心に 0.5 秒（50 サンプル × 6 ch）の窓を作る。
final class PinchDetector {
    enum Mode: Equatable {
        case detect        // 認識してイベントを出す
        case recordOnset   // 衝撃が来たら窓を録音用に返す
        case recordFree    // 一定間隔で窓を返す（「なし」クラスの収集用）
    }

    enum Output {
        case window([Float])
        case detected(label: String, confidence: Double)
    }

    struct Config {
        var jerkThreshold = 2.5   // G/s
        var maxGyro = 2.5         // rad/s
    }

    static let half = 25
    static let length = 50
    static let channels = 6
    private static let ringSize = 128

    var config = Config()
    var mode = Mode.detect
    var model: KNNModel?
    private(set) var lastJerk = 0.0

    private var ring = [Float](repeating: 0, count: PinchDetector.ringSize * PinchDetector.channels)
    private var jerkRing = [Double](repeating: 0, count: PinchDetector.ringSize)
    private var count = 0
    private var prevAccel = Vec3.zero
    /// 切り出し待ちのピーク（連続ピンチに備えて複数持つ）
    private var pending: [(index: Int, jerk: Double, onset: Int)] = []
    private var lastPeak = -1000
    private var lastDetected = -1000
    private var freeCounter = 0

    /// 連続ピンチを別々に数えるための最短間隔（サンプル数 = 0.18 秒）
    private static let minSpacing = 18

    func feed(_ s: MotionSample) -> Output? {
        let idx = count
        let slot = idx % Self.ringSize
        let values = [s.accel.x, s.accel.y, s.accel.z, s.gyro.x, s.gyro.y, s.gyro.z]
        for c in 0..<Self.channels { ring[slot * Self.channels + c] = Float(values[c]) }
        let jerk = (s.accel - prevAccel).length * 100
        prevAccel = s.accel
        jerkRing[slot] = jerk
        lastJerk = jerk
        count += 1

        if mode == .recordFree {
            pending.removeAll()
            freeCounter += 1
            guard freeCounter >= 40, count >= 60 else { return nil }
            freeCounter = 0
            return .window(extract(center: idx - Self.half))
        }

        let threshold = config.jerkThreshold
        if var last = pending.last, idx - last.onset <= 8 {
            // 立ち上がりから 8 サンプルの間はピークを探す
            if jerk > last.jerk {
                last.index = idx
                last.jerk = jerk
                pending[pending.count - 1] = last
                lastPeak = idx
            }
        } else if jerk > threshold && idx - lastPeak > Self.minSpacing && count > 60 {
            pending.append((idx, jerk, idx))
            lastPeak = idx
        }

        // ピークの後ろ 0.25 秒が溜まったものから切り出す
        guard let first = pending.first, idx - first.index >= Self.half - 1 else { return nil }
        pending.removeFirst()
        let w = extract(center: first.index)
        if mode == .recordOnset { return .window(w) }
        let nextOnset = pending.first?.onset
        let out = classify(w, peakIndex: first.index, peakJerk: first.jerk, nextOnset: nextOnset)
        if out != nil { lastDetected = first.index }
        return out
    }

    /// サンプリングが途切れた後に呼ぶ（古いデータでの誤検出を防ぐ）
    func reset() {
        count = 0
        pending.removeAll()
        lastPeak = -1000
        lastDetected = -1000
        freeCounter = 0
        prevAccel = .zero
    }

    private func extract(center: Int) -> [Float] {
        var out = [Float](repeating: 0, count: Self.length * Self.channels)
        for k in 0..<Self.length {
            let src = ((center - Self.half + k) % Self.ringSize + Self.ringSize) % Self.ringSize
            for c in 0..<Self.channels { out[k * Self.channels + c] = ring[src * Self.channels + c] }
        }
        return out
    }

    private func meanJerk(_ range: Range<Int>) -> Double {
        var sum = 0.0
        for i in range { sum += jerkRing[(i % Self.ringSize + Self.ringSize) % Self.ringSize] }
        return sum / Double(max(range.count, 1))
    }

    private func classify(_ w: [Float], peakIndex: Int, peakJerk: Double, nextOnset: Int?) -> Output? {
        if let model {
            // 学習データに似ていないものは拾わない（手を開く等の誤反応を防ぐ）
            guard let r = model.classify(GestureFeatures.extract(w)), r.label != GestureLabel.none.rawValue else { return nil }
            return .detected(label: r.label, confidence: r.confidence)
        }
        return heuristic(w, peakIndex: peakIndex, peakJerk: peakJerk, nextOnset: nextOnset)
    }

    /// 未学習時の簡易判定: 前後が静かで、短く鋭い衝撃だけを「つまむ」とみなす。
    /// 手を開く・指を動かすといった動きは衝撃がゆるやかで長いので、立ち上がりの鋭さと長さで除く。
    /// 連続ピンチでは前後に別のピンチの揺れが入るので、その分は除いて判定する
    private func heuristic(_ w: [Float], peakIndex: Int, peakJerk: Double, nextOnset: Int?) -> Output? {
        let thr = config.jerkThreshold
        // 直前 0.5 秒以内にピンチがあれば、その揺れの残りは「前が静か」の判定に使わない
        let recentPinch = peakIndex - lastDetected < 50
        let pre = recentPinch ? 0 : meanJerk((peakIndex - Self.half)..<(peakIndex - 6))
        // 次のピンチが始まっていたら、その手前までで「後ろが静か」を判定する
        let postEnd = min(peakIndex + Self.half - 1, nextOnset ?? Int.max)
        let post = postEnd > peakIndex + 10 ? meanJerk((peakIndex + 8)..<postEnd) : 0
        let quietPre = max(thr * 0.3, peakJerk * 0.2)
        let quietPost = max(thr * 0.35, peakJerk * 0.25)
        // はっきりした衝撃であること
        guard peakJerk >= thr * 1.3 else { return nil }
        // 短いこと: ピーク付近で強い揺れが続くサンプル数（ピンチは 0.1 秒以内に収まる）
        var strong = 0
        let end = min(peakIndex + 15, nextOnset ?? Int.max)
        for i in (peakIndex - 10)..<end where jerkRing[(i % Self.ringSize + Self.ringSize) % Self.ringSize] > peakJerk * 0.3 {
            strong += 1
        }
        guard strong <= 10 else { return nil }
        var gyroSq = 0.0
        for k in 0..<Self.length {
            for c in 3..<6 { let v = Double(w[k * Self.channels + c]); gyroSq += v * v }
        }
        let gyroRMS = (gyroSq / Double(Self.length)).squareRoot()
        guard pre < quietPre, post < quietPost, gyroRMS < config.maxGyro * 0.25 else { return nil }
        return .detected(label: GestureLabel.pinch.rawValue, confidence: 0.6)
    }
}
