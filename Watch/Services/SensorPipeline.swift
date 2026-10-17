import CoreMotion
import Foundation

extension Vec3 {
    init(_ a: CMAcceleration) { self.init(x: a.x, y: a.y, z: a.z) }
    init(_ r: CMRotationRate) { self.init(x: r.x, y: r.y, z: r.z) }
}

/// モーションの取得と検出処理。検出器はモーションキュー上でだけ触り、結果だけをメインへ渡す。
///
/// 読み取り頻度:
/// - ピンチ推定（手首の衝撃）を使うとき: 100Hz（衝撃の波形を取るため）
/// - それ以外: 通常 100Hz、省電力モード 50Hz（手首の姿勢と払う動きには十分）
/// - 腕を下ろしている間: 通常 3 秒後に 25Hz、省電力モード 2 秒後に 10Hz
final class SensorPipeline {
    let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        q.name = "SpatialCue.motion"
        return q
    }()

    /// メインスレッドで呼ばれる。reading は画面の更新間隔ごとと、イベント発生時に渡す
    var onUpdate: ((WristReading?, [WristEvent], PinchDetector.Output?) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// 腕を下ろしている間は読み取り頻度を下げる（モーションキュー上でのみ変更）
    var powerSaving = true
    /// 仮想 UI が動いている間は頻度を下げない
    var keepFullRate = false
    /// 省電力モード
    var lowPower = true
    /// ピンチ推定（手首の衝撃）が必要か。不要なら計算しない
    var needsPinch = false
    /// センサー画面を開いている間は画面をなめらかに更新する
    var fastUpdates = false
    private(set) var currentRate = 100.0
    private var lowSince: TimeInterval?
    private var lastPublish: TimeInterval = 0

    private let manager = CMMotionManager()
    private let wrist = WristGestureDetector()
    private let pinch = PinchDetector()
    private var frame = WristFrame()

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

    func setPower(lowPower: Bool, needsPinch: Bool) {
        queue.addOperation { [self] in
            self.lowPower = lowPower
            self.needsPinch = needsPinch
        }
    }

    func setFastUpdates(_ on: Bool) { queue.addOperation { [self] in fastUpdates = on } }

    /// 検出器の設定をモーションキュー上で変更する
    func configure(_ body: @escaping (_ wrist: WristGestureDetector, _ pinch: PinchDetector, _ frame: inout WristFrame) -> Void) {
        queue.addOperation { [self] in body(wrist, pinch, &frame) }
    }

    private func process(_ s: MotionSample) {
        let events = wrist.feed(s)
        // ピンチ推定は 100Hz 前提。使わないときや低頻度の間は計算しない
        let out = needsPinch && currentRate >= 100 ? pinch.feed(s) : nil
        adjustRate(s.t)
        // 画面の更新はセンサーの頻度よりずっと少なくてよい（描き直しは電池を使う）
        let interval = fastUpdates ? 0.03 : (lowPower ? 0.2 : 0.1)
        let due = s.t - lastPublish >= interval
        if due { lastPublish = s.t }
        let sendReading = due || !events.isEmpty
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
    /// 腕を下ろしたままなら低い頻度、それ以外は通常の頻度
    fileprivate func adjustRate(_ t: TimeInterval) {
        let active: Double = needsPinch ? 100 : (lowPower ? 50 : 100)
        let idle: Double = lowPower ? 10 : 25
        let idleAfter: Double = lowPower ? 2 : 3
        let armDown = wrist.reading.pose == .vertical && wrist.reading.elevation < 0
        if powerSaving && armDown && !keepFullRate {
            let since = lowSince ?? t
            lowSince = since
            if t - since > idleAfter && currentRate != idle { setRate(idle) }
        } else {
            lowSince = nil
            if currentRate != active { setRate(active) }
        }
    }

    private func setRate(_ hz: Double) {
        currentRate = hz
        manager.deviceMotionUpdateInterval = 1.0 / hz
        if hz >= 100 { pinch.reset() }
    }
}
