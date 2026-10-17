import Foundation

// 合成モーションでジェスチャー判定ロジックを検証する（Mac 上で実行）
// 実行: ./Tests/run.sh

var failures = 0
func check(_ cond: Bool, _ name: String) {
    print(cond ? "  ✓ \(name)" : "  ✗ \(name)")
    if !cond { failures += 1 }
}

/// ひねり角 roll・上下角 elev（度）から手首フレームの重力ベクトルを作る
func gravity(roll: Double, elev: Double) -> Vec3 {
    let r = roll * .pi / 180, e = elev * .pi / 180
    return Vec3(x: -sin(e), y: cos(e) * sin(r), z: -cos(e) * cos(r))
}

final class Sim {
    var t = 0.0
    var dt = 0.01   // サンプリング間隔（0.02 = 50Hz）
    var roll = 0.0, elev = -80.0
    var wrist = WristGestureDetector()
    var pinch = PinchDetector()
    var events: [WristEvent] = []
    var detections: [String] = []
    var windows: [[Float]] = []
    var rng = SystemRandomNumberGenerator()

    func step(accel: Vec3 = .zero, gyro: Vec3 = .zero) {
        let noise = { Double.random(in: -0.002...0.002) }
        let e = elev * .pi / 180
        let s = MotionSample(t: t, gravity: gravity(roll: roll, elev: elev),
                             accel: Vec3(x: accel.x + noise(), y: accel.y + noise(), z: accel.z + noise()),
                             gyro: gyro, forearm: Vec3(x: cos(e), y: 0, z: sin(e)))
        events += wrist.feed(s)
        switch pinch.feed(s) {
        case .detected(let label, _)?: detections.append(label)
        case .window(let w)?: windows.append(w)
        case nil: break
        }
        t += dt
    }

    func hold(_ seconds: Double) { for _ in 0..<Int((seconds / dt).rounded()) { step() } }

    func move(roll r: Double? = nil, elev e: Double? = nil, over seconds: Double) {
        let n = max(Int((seconds / dt).rounded()), 1)
        let r0 = roll, e0 = elev, r1 = r ?? roll, e1 = e ?? elev
        let gyroX = (r1 - r0) * .pi / 180 / seconds
        for i in 1...n {
            let k = Double(i) / Double(n)
            roll = r0 + (r1 - r0) * k
            elev = e0 + (e1 - e0) * k
            step(gyro: Vec3(x: gyroX, y: 0, z: 0))
        }
    }

    /// 減衰する短い振動（つまむ動作の衝撃）
    func tap(amplitude: Double, freq: Double = 30) {
        for i in 0..<20 {
            let tt = Double(i) * 0.01
            let a = amplitude * exp(-tt * 25) * sin(2 * .pi * freq * tt)
            step(accel: Vec3(x: a * 0.3, y: a, z: a * 0.6))
        }
    }

    func count(_ e: WristEvent) -> Int { events.filter { $0 == e }.count }
}

L10n.ui = .ja
L10n.speech = .ja

print("■ 手首ジェスチャー")
do {
    let s = Sim()
    s.hold(1)
    s.move(roll: 0, elev: 10, over: 0.4)
    s.hold(0.5)
    check(s.count(.glanceBegan) == 1, "腕を上げて文字盤を見ると glanceBegan")

    s.move(roll: 175, over: 0.25); s.hold(0.6)
    check(s.count(.palmUpBegan) == 1, "手のひらを上に向けると palmUpBegan")
    check(s.count(.palmGazeBegan) == 1, "AirPods なしでは手のひらを上げるだけで palmGazeBegan")

    s.move(roll: 0, over: 0.2); s.hold(0.3)
    check(s.count(.flipToFace) == 1, "手のひら → 表へ素早く返すと flipToFace")
    check(s.count(.palmUpEnded) == 0, "  → palmUpEnded は出ない")
    check(s.count(.palmGazeEnded) == 1, "  → palmGazeEnded が出る")

    for _ in 0..<5 { s.step(gyro: Vec3(x: 0, y: 0, z: 7)) }
    s.hold(0.3)
    check(s.events.contains(.flick(1)), "見ている最中に手首を払うと flick")

    s.move(roll: 175, over: 0.25); s.hold(0.5)
    s.move(roll: 175, elev: -85, over: 0.6); s.hold(0.6)
    check(s.count(.palmUpEnded) == 1, "手のひらのまま腕を下ろすと palmUpEnded")
    check(s.count(.flipToFace) == 1, "  → flipToFace は増えない")

    s.move(roll: 0, elev: -85, over: 0.3); s.hold(0.5)
    let before = s.count(.palmUpBegan)
    s.move(roll: 175, over: 0.25); s.hold(1.0)
    check(s.count(.palmUpBegan) == before, "腕を下ろしたままの回転では反応しない")
}

do {
    let s = Sim()
    s.wrist.config.requireHeadLook = true
    var look = 0.0
    s.wrist.head = { HeadSample(pitch: 0, yaw: 0, look: look, downSign: -1) }
    s.move(roll: 0, elev: 10, over: 0.4); s.hold(0.6)
    check(s.count(.glanceBegan) == 0, "AirPods ゲート: 頭が正面のままなら glance しない")
    look = 0.9
    s.hold(0.4)
    check(s.count(.glanceBegan) == 1, "AirPods ゲート: 下を向くと glance する")
}

print("■ 手のひらを見ているか（頭の向き × 腕の向きから推定した手のひらの位置）")
do {
    let s = Sim()
    var head = HeadSample(pitch: -30, yaw: 10, look: 1, downSign: -1)
    s.wrist.head = { head }
    s.move(roll: 175, elev: 15, over: 0.5); s.hold(0.4)
    // この姿勢で校正
    let r = s.wrist.reading
    s.wrist.config.palmCalibration = PalmCalibration(headPitch: head.pitch, headYaw: head.yaw,
                                                    palmElevation: r.palmElevation, palmAzimuth: r.palmAzimuth)
    s.hold(0.4)
    check(s.count(.palmGazeBegan) == 1, "校正した姿勢で手のひらを見ている（ずれ \(Int(s.wrist.reading.gazeError ?? -1))°）")
    head.pitch = 10   // 顔を上げて正面を見る
    s.hold(0.5)
    check(s.count(.palmGazeEnded) == 1, "顔を上げると見ていない判定（ずれ \(Int(s.wrist.reading.gazeError ?? -1))°）")
    head.pitch = -30; head.yaw = 60   // 横を向く
    s.hold(0.5)
    check(s.count(.palmGazeBegan) == 1, "横を向いたままでは見ていない（ずれ \(Int(s.wrist.reading.gazeError ?? -1))°）")
    head.yaw = 10
    s.move(elev: 50, over: 0.4); s.hold(0.4)
    let shift = s.wrist.reading.palmElevation - r.palmElevation
    check(abs((s.wrist.reading.gazeError ?? 0) - abs(shift)) < 1.5, "手だけ動かすと、手のひらの移動分（\(Int(shift))°）だけずれる")
    head.pitch = -30 + (s.wrist.reading.palmElevation - r.palmElevation)
    s.hold(0.5)
    check(s.count(.palmGazeBegan) == 2, "手を追って目線を上げると再び見ている（ずれ \(Int(s.wrist.reading.gazeError ?? -1))°）")
}

do {
    // 頭の向きを使わない設定: 頭がよそを向いていても、手首だけで「手のひらを見ている」になる
    let s = Sim()
    s.wrist.head = { HeadSample(pitch: 40, yaw: 90, look: 0, downSign: -1) }
    s.wrist.config.palmCalibration = PalmCalibration(headPitch: -30, headYaw: 0, palmElevation: -30, palmAzimuth: 0)
    s.wrist.config.useHead = false
    s.move(roll: 175, elev: 15, over: 0.5); s.hold(0.6)
    check(s.count(.palmGazeBegan) == 1, "頭の向きを使わない設定では、手首だけで手のひらの判定をする")
}

do {
    // 省電力モード（50Hz）でも手首のジェスチャーを判定できる
    let s = Sim()
    s.dt = 0.02
    s.hold(1)
    s.move(roll: 0, elev: 10, over: 0.4); s.hold(0.5)
    s.move(roll: 175, over: 0.25); s.hold(0.6)
    s.move(roll: 0, over: 0.2); s.hold(0.3)
    for _ in 0..<3 { s.step(gyro: Vec3(x: 0, y: 0, z: 7)) }
    s.hold(0.3)
    check(s.count(.glanceBegan) >= 1 && s.count(.palmGazeBegan) == 1 && s.count(.flipToFace) == 1 && s.events.contains(.flick(1)),
          "50Hz（省電力モード）でも 見る・手のひら・表に返す・払う を判定")
}

print("■ つまむ検出（未学習ヒューリスティック）")
do {
    let s = Sim()
    s.move(roll: 0, elev: 10, over: 0.4); s.hold(1)
    s.tap(amplitude: 0.08); s.hold(0.6)
    check(s.detections == ["pinch"], "静止中の短い衝撃 → つまむ")
    s.detections.removeAll()
    s.tap(amplitude: 0.005); s.hold(0.6)
    check(s.detections.isEmpty, "微小な振動は無視")
    s.move(roll: 90, over: 0.3); s.move(roll: 0, over: 0.3); s.hold(0.6)
    check(s.detections.isEmpty, "腕のひねり動作は無視")
    // 手を開く: ゆるやかに立ち上がって長く続く揺れ
    for i in 0..<30 {
        let tt = Double(i) * 0.01
        let a = 0.12 * sin(.pi * tt / 0.3) * sin(2 * .pi * 12 * tt)
        s.step(accel: Vec3(x: a * 0.5, y: a, z: a * 0.4))
    }
    s.hold(0.6)
    check(s.detections.isEmpty, "手を開く（ゆるやかで長い揺れ）は無視（\(s.detections)）")
}

do {
    let s = Sim()
    s.move(roll: 175, elev: 10, over: 0.4); s.hold(1)
    for _ in 0..<3 { s.tap(amplitude: 0.08); s.hold(0.12) }
    s.hold(0.6)
    check(s.detections.count == 3, "0.3 秒間隔の 3 連続ピンチを数える（\(s.detections.count) 回）")
    s.detections.removeAll()
    s.hold(1)
    for _ in 0..<3 { s.tap(amplitude: 0.08); s.hold(0.02) }
    s.hold(0.6)
    check(s.detections.count == 3, "0.22 秒間隔の速い 3 連続ピンチも数える（\(s.detections.count) 回）")
}

print("■ 学習（k 近傍法）")
do {
    let s = Sim()
    s.pinch.mode = .recordOnset
    s.move(roll: 0, elev: 10, over: 0.4); s.hold(1)
    for _ in 0..<10 { s.tap(amplitude: Double.random(in: 0.07...0.10), freq: 30); s.hold(0.6) }
    let pinchWindows = s.windows; s.windows.removeAll()
    for _ in 0..<10 { s.tap(amplitude: Double.random(in: 0.25...0.35), freq: 12); s.hold(0.6) }
    let fistWindows = s.windows
    check(pinchWindows.count == 10 && fistWindows.count == 10, "衝撃ごとに窓を録音（\(pinchWindows.count), \(fistWindows.count)）")

    let samples = pinchWindows.map { ("pinch", GestureFeatures.extract($0)) } + fistWindows.map { ("fist", GestureFeatures.extract($0)) }
    let model = KNNModel(samples: samples.map { (label: $0.0, features: $0.1) })
    check(model != nil, "モデルを構築")
    check((model?.looAccuracy ?? 0) >= 0.9, "交差検証精度 \(Int((model?.looAccuracy ?? 0) * 100))%")

    s.pinch.model = model
    s.pinch.mode = .detect
    s.detections.removeAll()
    s.tap(amplitude: 0.085, freq: 30); s.hold(0.6)
    s.tap(amplitude: 0.3, freq: 12); s.hold(0.6)
    check(s.detections == ["pinch", "fist"], "新しい動作を分類: \(s.detections)")

    // 学習データに似ていない衝撃は拾わない
    s.detections.removeAll()
    s.hold(1)
    s.tap(amplitude: 0.2, freq: 70); s.hold(0.6)
    check(s.detections.isEmpty, "学習済みモデルは似ていない衝撃を拾わない（\(s.detections)）")
}

print("■ 頭ジェスチャー（AirPods）")
do {
    let d = HeadGestureDetector()
    var got: [HeadEvent] = []
    var t = 0.0
    func run(_ f: (Double) -> (Double, Double), _ seconds: Double) {
        let start = t
        while t - start < seconds { let (p, y) = f(t - start); if let e = d.feed(t: t, pitch: p, yaw: y) { got.append(e) }; t += 0.04 }
    }
    run({ _ in (0, 0) }, 1)
    run({ k in (-15 * sin(.pi * min(k / 0.5, 1)), 0) }, 1.0)
    check(got == [.nod], "うなずき")
    got.removeAll()
    run({ _ in (0, 0) }, 1)
    run({ k in (0, 20 * sin(2 * .pi * min(k / 0.7, 1))) }, 1.0)
    check(got == [.shake], "首振り")
    got.removeAll()
    run({ k in (-25 * min(k / 0.4, 1), 0) }, 2.0)
    check(got.isEmpty, "下を向いたまま（時計を見る）は誤検出しない")

    var c = HeadCalibration(); c.neutralPitch = 5; c.lookPitch = 30
    check(abs(c.lookAmount(pitch: 17.5) - 0.5) < 1e-9 && c.lookAmount(pitch: 0) == 0, "校正: 下向きが正の向きでも動く")
}

print("■ 仮想 UI（時刻とメディア）")
do {
    var log: [String] = []
    let air = AirController()
    air.effects = .init(
        speak: { log.append("話:" + $0.text) }, stopSpeaking: { log.append("話停止") }, pop: { log.append("ポン") },
        tick: {}, startTimeReadout: { log.append("時刻開始") }, stopTimeReadout: { log.append("時刻停止") },
        setVolume: { log.append(String(format: "音量:%.2f", $0)) }, menu: { log.append("メニュー:" + $0.title) })
    air.config.directMedia = false
    var t = 0.0
    var r = WristReading()
    func run(_ seconds: Double, roll: Double? = nil, elev: Double? = nil) {
        let n = Int(seconds * 30)
        let r0 = r.roll, e0 = r.elevation
        for i in 1...max(n, 1) {
            let k = Double(i) / Double(max(n, 1))
            if let roll { r.roll = r0 + (roll - r0) * k }
            if let elev { r.elevation = e0 + (elev - e0) * k }
            r.gyro = (roll != nil && roll != r0) || (elev != nil && elev != e0) ? 1.0 : 0.05
            t += 1.0 / 30
            air.update(t: t, reading: r)
        }
    }
    func has(_ x: String) -> Bool { log.contains(x) }

    r.roll = 175; r.elevation = 10
    air.wrist(.palmGazeBegan, t: t)
    check(air.mode == .ready && has("ポン"), "手のひらを見る → 「ポン」で準備完了")
    log.removeAll()
    check(air.pinch(t: t) && air.mode == .ready && log.isEmpty, "準備完了中のピンチは何もしない（画面側にも渡さない）")

    air.wrist(.flipToFace, t: t); r.roll = 0
    check(air.mode == .clock && has("時刻開始"), "表へ返す → 時刻（読み上げ＋振動）")
    air.wrist(.glanceEnded, t: t)
    check(air.mode == .idle && has("時刻停止"), "姿勢を崩すと読み上げが止まる")

    log.removeAll()
    air.syncVolume(0.4)
    air.wrist(.flipToFace, t: t)
    air.pinch(t: t); run(0.1)
    run(0.6, roll: 30)
    check(air.mode == .volume && has("話:音量 40%"), "時計でピンチして動かす → 音量スライダー")
    check(log.contains("話:80%") || log.contains("話:90%"), "動かすと%を読み上げ: \(log.filter { $0.hasPrefix("話:") })")
    run(1.0)
    check(air.mode == .clock && log.contains { $0.hasPrefix("音量:0.9") || $0.hasPrefix("音量:0.8") }, "止めると音量が確定して時計に戻る")

    log.removeAll()
    air.pinch(t: t); run(1.0)
    check(air.mode == .menu && log.last == "話:メニュー。1回 再生、2回 次、3回 前", "時計でピンチ 1 回 → メニュー")
    air.pinch(t: t); run(1.0)
    check(has("メニュー:再生・停止") && air.mode == .clock, "メニューでピンチ 1 回 → 再生・停止")
    air.pinch(t: t); run(1.0)
    air.pinch(t: t); run(0.2); air.pinch(t: t); run(1.0)
    check(has("メニュー:次の曲"), "メニューでピンチ 2 回 → 次の曲")
    air.pinch(t: t); run(1.0)
    air.pinch(t: t); run(0.2); air.pinch(t: t); run(0.2); air.pinch(t: t); run(1.0)
    check(has("メニュー:前の曲"), "メニューでピンチ 3 回 → 前の曲")

    // メニューを省略（既定）: ダブルタップ = 再生・停止、払う = 曲送り・曲戻し、竜頭 = 音量
    air.config.directMedia = true
    log.removeAll()
    air.pinch(t: t)
    check(has("メニュー:再生・停止") && air.mode == .clock, "メニュー省略: ダブルタップ 1 回ですぐ再生・停止（待ちなし）")
    log.removeAll()
    check(air.flick(1, t: t) && has("メニュー:次の曲"), "メニュー省略: 右に払う → 次の曲")
    check(air.flick(-1, t: t) && has("メニュー:前の曲"), "メニュー省略: 左に払う → 前の曲")
    log.removeAll()
    air.config.maxVolume = 0.7
    air.setVolume(0.95, t: t)
    check(air.state.volume <= 0.7 + 1e-9 && log.contains { $0.hasPrefix("音量:") }, "竜頭の音量も上限を超えない（\(Int(air.state.volume * 100))%）")
    air.config.maxVolume = 1
    air.cancel(t: t)
    check(!air.flick(1, t: t), "待機中の払う動作は曲送りにしない")
    air.config.directMedia = false

    air.cancel(t: t)
    check(air.mode == .idle && air.pinch(t: t) == false, "待機中のピンチは仮想 UI では処理しない")

    // 安全装置: 音量の上限
    log.removeAll()
    air.config.maxVolume = 0.6
    air.syncVolume(0.5)
    r.roll = 0
    air.wrist(.flipToFace, t: t)
    air.pinch(t: t); run(0.1)
    run(0.6, roll: 40)
    run(1.0)
    check(air.state.volume <= 0.6 + 1e-9 && !log.contains("話:70%"), "音量は上限（60%）を超えない: \(Int(air.state.volume * 100))%")
}

print("■ 言語")
do {
    L10n.apply(app: .en, speech: .app)
    check(AirPhrase.volume(40).text == "Volume 40 percent" && MenuAction.nextTrack.title == "Next track", "英語の画面・読み上げ")
    L10n.apply(app: .en, speech: .ja)
    check(AirPhrase.volume(40).text == "音量 40%" && tr("時計", "Clock") == "Clock", "画面は英語・読み上げは日本語")
    L10n.apply(app: .ja, speech: .app)
}

print(failures == 0 ? "\nすべて成功" : "\n\(failures) 件失敗")
exit(failures == 0 ? 0 : 1)
