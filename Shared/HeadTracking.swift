import Foundation

/// 「正面」と「手首の時計を見ている」ときの頭のピッチを記録し、見ている度合い（0…1.5）を返す。
/// 符号の向き（下向きが正か負か）は校正で吸収する。
struct HeadCalibration: Codable {
    var neutralPitch = 0.0
    var lookPitch = -30.0   // 未校正時の仮値（下向きが負と仮定）
    var calibrated = false

    /// 下を向いたときにピッチが増えるなら +1、減るなら -1
    var downSign: Double { lookPitch - neutralPitch >= 0 ? 1 : -1 }

    func lookAmount(pitch: Double) -> Double {
        let span = lookPitch - neutralPitch
        guard abs(span) > 3 else { return 0 }
        return clamp((pitch - neutralPitch) / span, 0, 1.5)
    }

    static func load(key: String) -> HeadCalibration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let c = try? JSONDecoder().decode(HeadCalibration.self, from: data) else { return HeadCalibration() }
        return c
    }

    func save(key: String) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// 頭の角度（度）の短い履歴から、うなずき／首振りを検出する。
/// 向きの符号に依存しないよう「一方向に振れて元に戻る」形で判定する。
final class HeadGestureDetector {
    private struct Pose {
        let t: TimeInterval
        let pitch: Double
        let yaw: Double
    }

    var nodDepth = 8.0      // うなずきの最小振れ幅（度）
    var shakeWidth = 16.0   // 首振りの最小振れ幅（度）
    var window = 0.9        // 判定窓（秒）

    private var history: [Pose] = []
    private var lastEvent: TimeInterval = -10

    func feed(t: TimeInterval, pitch: Double, yaw: Double) -> HeadEvent? {
        history.append(Pose(t: t, pitch: pitch, yaw: yaw))
        while let first = history.first, t - first.t > window { history.removeFirst() }
        guard t - lastEvent > 0.9, history.count >= 6,
              let start = history.first, let now = history.last,
              now.t - start.t > window * 0.5 else { return nil }

        let dp = history.map { $0.pitch - start.pitch }
        let dy = history.map { wrapDegrees($0.yaw - start.yaw) }
        let pitchRange = dp.max()! - dp.min()!
        let yawRange = dy.max()! - dy.min()!
        let nowP = now.pitch - start.pitch
        let nowY = wrapDegrees(now.yaw - start.yaw)

        // うなずき: ピッチが一方向に振れて戻る。ヨーはあまり動かない
        if let ext = dp.max(by: { abs($0) < abs($1) }), abs(ext) > nodDepth,
           abs(nowP) < abs(ext) * 0.35, yawRange < max(abs(ext) * 0.8, 6) {
            return fire(.nod, at: t)
        }
        // 首振り: ヨーが左右両方に振れて戻る。ピッチはあまり動かない
        if dy.max()! > shakeWidth * 0.4, dy.min()! < -shakeWidth * 0.4, yawRange > shakeWidth,
           abs(nowY) < yawRange * 0.3, pitchRange < yawRange * 0.6 {
            return fire(.shake, at: t)
        }
        return nil
    }

    private func fire(_ e: HeadEvent, at t: TimeInterval) -> HeadEvent {
        lastEvent = t
        history.removeAll()
        return e
    }
}
