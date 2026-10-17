import CoreMotion
import Foundation

/// 最新の頭の状態。モーションキューからも読むのでロックで守る。
final class HeadState {
    enum Source {
        case phone, watch

        var title: String { self == .phone ? tr("iPhone経由", "via iPhone") : tr("時計直結", "direct to Watch") }
    }

    struct Snapshot {
        var pitch: Double
        var yaw: Double
        var look: Double
        var downSign: Double
        var source: Source
        var time: Date
    }

    static let shared = HeadState()

    private let lock = NSLock()
    private var latest: Snapshot?

    func update(_ s: Snapshot) {
        lock.lock()
        latest = s
        lock.unlock()
    }

    func current(maxAge: TimeInterval = 0.7) -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let l = latest, Date().timeIntervalSince(l.time) < maxAge else { return nil }
        return l
    }
}

/// AirPods が時計に直接つながっている場合に、時計側で頭の向きを読む。
/// 通常は AirPods は iPhone 側につながるので、その場合は PhoneLink 経由の値が使われる。
@MainActor
final class HeadLink: NSObject, ObservableObject {
    static let calibrationKey = "watchHeadCalibration"

    @Published private(set) var directConnected = false
    @Published var calibration = HeadCalibration.load(key: HeadLink.calibrationKey) {
        didSet { calibration.save(key: Self.calibrationKey) }
    }

    var onEvent: ((HeadEvent) -> Void)?
    private(set) var lastPitch = 0.0

    private let manager = CMHeadphoneMotionManager()
    private let gestures = HeadGestureDetector()

    func start() {
        manager.delegate = self
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let m else { return }
            MainActor.assumeIsolated { self?.handle(m) }
        }
    }

    /// 頭の向きを使わない設定のときは止める（AirPods と時計の電池を使わない）
    func stop() {
        manager.stopDeviceMotionUpdates()
        directConnected = false
    }

    func captureNeutral() { calibration.neutralPitch = lastPitch }

    func captureLook() {
        calibration.lookPitch = lastPitch
        calibration.calibrated = true
    }

    private func handle(_ m: CMDeviceMotion) {
        let pitch = m.attitude.pitch * 180 / .pi
        let yaw = m.attitude.yaw * 180 / .pi
        lastPitch = pitch
        HeadState.shared.update(.init(pitch: pitch, yaw: yaw, look: calibration.lookAmount(pitch: pitch),
                                      downSign: calibration.downSign, source: .watch, time: Date()))
        if let e = gestures.feed(t: m.timestamp, pitch: pitch, yaw: yaw) { onEvent?(e) }
    }
}

extension HeadLink: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.directConnected = true }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.directConnected = false }
    }
}
