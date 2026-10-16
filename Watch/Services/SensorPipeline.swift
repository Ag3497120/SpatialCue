import CoreMotion
import Foundation

extension Vec3 {
    init(_ a: CMAcceleration) { self.init(x: a.x, y: a.y, z: a.z) }
    init(_ r: CMRotationRate) { self.init(x: r.x, y: r.y, z: r.z) }
}

/// 100Hz のモーション取得と検出処理。検出器はモーションキュー上でだけ触り、結果だけをメインへ渡す。
final class SensorPipeline {
    let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        q.name = "SpatialCue.motion"
        return q
    }()

    /// メインスレッドで呼ばれる。reading は約 33Hz とイベント発生時に渡す
    var onUpdate: ((WristReading?, [WristEvent], PinchDetector.Output?) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// 腕を下ろしている間は読み取り頻度を下げる（モーションキュー上でのみ変更）
    var powerSaving = true
    /// 仮想 UI が動いている間は頻度を下げない
    var keepFullRate = false
    private(set) var currentRate = 100.0
    private var lowSince: TimeInterval?

    private let manager = CMMotionManager()
    private let wrist = WristGestureDetector()
    private let pinch = PinchDetector()
    private var frame = WristFrame()
    private var tick = 0

    init() {
        wrist.head = {
            HeadState.shared.current().map { HeadSample(pitch: $0.pitch, yaw: $0.yaw, look: $0.look, downSign: $0.downSign) }
        }
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 100
        // 前腕の向きを世界座標で得るため、重力が z 軸に揃う基準座標系を使う。
        // 磁気センサーで補正する .xArbitraryCorrectedZVertical は電力を使うので使わない（ヨーのずれは手のひら校正で吸収）
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] m, _ in
            guard let self, let m else { return }
            let f = self.frame
            // 回転行列の 1 行目 = 端末の x 軸（竜頭側）を基準座標系で表したもの
            let r = m.attitude.rotationMatrix
            let deviceX = Vec3(x: r.m11, y: r.m12, z: r.m13)
            self.process(MotionSample(t: m.timestamp, gravity: f.apply(Vec3(m.gravity)),
                                      accel: f.apply(Vec3(m.userAcceleration)), gyro: f.apply(Vec3(m.rotationRate)),
                                      forearm: f.crownTowardHand ? deviceX : deviceX * -1))
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    func setPowerSaving(_ on: Bool) { queue.addOperation { [self] in powerSaving = on } }

    func setKeepFullRate(_ on: Bool) { queue.addOperation { [self] in keepFullRate = on } }

    /// 検出器の設定をモーションキュー上で変更する
    func configure(_ body: @escaping (_ wrist: WristGestureDetector, _ pinch: PinchDetector, _ frame: inout WristFrame) -> Void) {
        queue.addOperation { [self] in body(wrist, pinch, &frame) }
    }

    private func process(_ s: MotionSample) {
        let events = wrist.feed(s)
        // ピンチ検出は 100Hz 前提なので、低頻度の間は止める
        let out = currentRate >= 100 ? pinch.feed(s) : nil
        adjustRate(s.t)
        tick += 1
        let sendReading = tick % 3 == 0 || !events.isEmpty
        guard sendReading || out != nil else { return }
        var r: WristReading?
        if sendReading {
            r = wrist.reading
            r?.jerk = pinch.lastJerk
        }
        DispatchQueue.main.async { self.onUpdate?(r, events, out) }
    }
}

extension SensorPipeline {
    /// 腕を 3 秒下ろしたままなら 25Hz、それ以外は 100Hz
    fileprivate func adjustRate(_ t: TimeInterval) {
        let armDown = wrist.reading.pose == .vertical && wrist.reading.elevation < 0
        if powerSaving && armDown && !keepFullRate {
            let since = lowSince ?? t
            lowSince = since
            if t - since > 3 && currentRate != 25 { setRate(25) }
        } else {
            lowSince = nil
            if currentRate != 100 { setRate(100) }
        }
    }

    private func setRate(_ hz: Double) {
        currentRate = hz
        manager.deviceMotionUpdateInterval = 1.0 / hz
        if hz >= 100 { pinch.reset() }
    }
}
