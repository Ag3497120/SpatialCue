import Accessibility
import Combine
import SwiftUI
import WatchKit

/// ピンチの入力元
enum PinchSource {
    case wrist, doubleTap, quickAction, nod

    var title: String {
        switch self {
        case .wrist: return tr("手首", "Wrist")
        case .doubleTap: return tr("ダブルタップ", "Double Tap")
        case .quickAction: return tr("クイックアクション", "Quick Action")
        case .nod: return tr("うなずき", "Nod")
        }
    }
}

/// ピンチを認識したときに一瞬表示するマーク
struct PinchFlash: Equatable {
    var id: Int
    var accepted: Bool      // false = 認識したが安全装置などで無視した
    var source: PinchSource
    var count: Int          // 回数を数えている途中なら 2, 3 …
}

/// 画面。アプリ一覧は無く、設定は iPhone アプリで行う。学習とセンサーはホームから開く
enum Screen: String, Hashable {
    case training, sensors
}

@MainActor
final class AppModel: ObservableObject {
    // MARK: 状態

    @Published var path: [Screen] = []
    @Published private(set) var reading = WristReading()
    @Published private(set) var head: HeadState.Snapshot?
    @Published private(set) var toast: String?
    @Published private(set) var lastGesture = "—"
    @Published private(set) var recordingLabel: GestureLabel?
    @Published private(set) var recordedThisRun = 0
    @Published private(set) var air = AirController.State()
    @Published private(set) var pinchFlash: PinchFlash?
    private var flashSequence = 0

    /// iPhone アプリから同期される設定
    @Published private(set) var settings: WristSettings = {
        let s = WristSettings.load()
        s.applyLanguage()
        return s
    }()
    @Published private(set) var palmCalibration: PalmCalibration? {
        didSet {
            if let c = palmCalibration, let data = try? JSONEncoder().encode(c) {
                UserDefaults.standard.set(data, forKey: "palmCalibration")
            } else {
                UserDefaults.standard.removeObject(forKey: "palmCalibration")
            }
            pushConfig()
            sendStatus()
        }
    }

    // MARK: サービス

    let training = TrainingStore()
    let headLink = HeadLink()
    let phone = PhoneLink()
    let runtime = RuntimeSession()
    let workout = WorkoutKeeper()
    private let pipeline = SensorPipeline()
    private let teller = TimeTeller()
    private let sfx = SoundFX()
    let airController = AirController()
    private var cancellables: Set<AnyCancellable> = []
    private var started = false
    private var readoutTask: Task<Void, Never>?
    private var fullRateRequested = false

    var motionAvailable: Bool { pipeline.isAvailable }

    /// イヤホンをつないでいるか（iPhone の音声出力がイヤホン、または AirPods が時計に直接つながっている）
    var headphonesOn: Bool { phone.headphonesOn || headLink.directConnected }

    /// 音を出してよいか（安全装置をオンにしたときだけ、イヤホンが無いと振動だけ）
    var canUseSound: Bool {
        if !settings.vibrationOnlyWithoutHeadphones { return true }
        // Watch のスピーカーで鳴らす設定ならイヤホンではないので鳴らさない
        return settings.soundOutput == .auto && headphonesOn
    }

    init() {
        palmCalibration = UserDefaults.standard.data(forKey: "palmCalibration")
            .flatMap { try? JSONDecoder().decode(PalmCalibration.self, from: $0) }

        pipeline.onUpdate = { [weak self] r, events, out in
            MainActor.assumeIsolated { self?.handle(reading: r, events: events, output: out) }
        }
        headLink.onEvent = { [weak self] e in self?.handleHead(e) }
        phone.onHeadEvent = { [weak self] e in self?.handleHead(e) }
        phone.onSystemVolume = { [weak self] v in
            self?.airController.syncVolume(v)
            self?.teller.speechVolume = Float(v)
        }
        phone.onSettings = { [weak self] s in self?.apply(s) }
        phone.onCommand = { [weak self] c in self?.perform(c) }
        airController.effects = .init(
            speak: { [weak self] phrase in self?.speak(phrase.text) },
            stopSpeaking: { [weak self] in self?.stopSpeaking() },
            pop: { [weak self] in self?.pop() },
            tick: { WKInterfaceDevice.current().play(.click) },
            startTimeReadout: { [weak self] in self?.startTimeReadoutAfterFlip() },
            stopTimeReadout: { [weak self] in self?.stopTimeReadout() },
            setVolume: { [weak self] v in self?.setSystemVolume(v) },
            menu: { [weak self] a in self?.menuAction(a) })
        training.$model
            .sink { [weak self] m in self?.pipeline.configure { _, p, _ in p.model = m } }
            .store(in: &cancellables)
        // 子オブジェクトの変化も画面に反映する
        for child in [training.objectWillChange, headLink.objectWillChange, phone.objectWillChange,
                      runtime.objectWillChange, workout.objectWillChange] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        phone.$reachable
            .removeDuplicates()
            .sink { [weak self] r in if r { self?.sendStatus() } }
            .store(in: &cancellables)
        pushConfig()
    }

    func start() {
        guard !started else { return }
        started = true
        phone.activate()
        headLink.start()
        pipeline.start()
        becameActive()
    }

    func becameActive() {
        applyResidency()
    }

    // MARK: 設定（iPhone から）

    private func apply(_ s: WristSettings) {
        guard s != settings else { return }
        let residencyChanged = s.workoutMode != settings.workoutMode || s.keepRunning != settings.keepRunning
        s.applyLanguage()
        settings = s
        s.save()
        pushConfig()
        if residencyChanged { applyResidency() }
        if !s.gesturesEnabled, airController.isActive {
            airController.cancel(t: ProcessInfo.processInfo.systemUptime)
            syncAir()
        }
    }

    private func perform(_ c: WatchCommand) {
        switch c {
        case .calibratePalm: startPalmCalibration()
        case .flipPalmYaw: toggleYawSign()
        case .clearPalm: palmCalibration = nil
        case .testTime: tellTime()
        }
    }

    /// 常駐の方法を切り替える: ワークアウト（無制限）> 延長実行（最長 1 時間）> なし
    private func applyResidency() {
        guard started else { return }
        if Edition.isStable {
            // 安定版は常駐しない（アプリを開いている間だけ動く）
            runtime.stop()
            workout.stop()
        } else if settings.workoutMode {
            runtime.stop()
            workout.start()
        } else {
            workout.stop()
            settings.keepRunning ? runtime.start() : runtime.stop()
        }
        sendStatus()
    }

    private var residencyText: String {
        workout.active ? tr("ワークアウト", "Workout")
            : runtime.active ? tr("延長実行", "Extended runtime")
            : settings.workoutMode ? tr("ワークアウト開始待ち", "Waiting for workout") : tr("なし", "None")
    }

    private func sendStatus() {
        phone.sendStatus(palmCalibrated: palmCalibration != nil, residency: residencyText)
    }

    private func pushConfig() {
        let s = settings
        let towardHand: Bool
        switch s.wristSetup {
        case .auto:
            let dev = WKInterfaceDevice.current()
            towardHand = (dev.wristLocation == .left) == (dev.crownOrientation == .right)
        case .crownTowardHand: towardHand = true
        case .crownTowardElbow: towardHand = false
        }
        let jerkThr = 5.0 - 3.8 * s.pinchSensitivity        // 感度 0 → 5.0 G/s, 1 → 1.2 G/s
        let flickThr = 8.0 - 5.0 * s.flickSensitivity       // 感度 0 → 8 rad/s, 1 → 3 rad/s
        let palm = palmCalibration
        pipeline.setPowerSaving(s.powerSaving)
        airController.config.invertX = s.invertVolumeX
        airController.config.maxVolume = s.maxVolume
        airController.config.directMedia = s.directMedia
        pipeline.configure { w, p, f in
            w.config.useHead = s.useHeadTracking
            w.config.requireHeadLook = s.requireHeadLook
            w.config.headLookThreshold = s.headLookThreshold
            w.config.flickThreshold = flickThr
            w.config.palmCalibration = palm
            w.config.gazeThreshold = s.gazeThreshold
            p.config.jerkThreshold = jerkThr
            f.crownTowardHand = towardHand
        }
    }

    // MARK: センサー結果の処理

    private func handle(reading r: WristReading?, events: [WristEvent], output: PinchDetector.Output?) {
        let now = ProcessInfo.processInfo.systemUptime
        if let r {
            reading = r
            head = HeadState.shared.current()
            airController.update(t: now, reading: r)
        }
        if settings.gesturesEnabled {
            for e in events {
                airController.wrist(e, t: now)
                handle(e)
            }
        }
        if let output { handle(output) }
        syncAir()
        // 仮想 UI・学習中は、腕を下ろしても頻度を落とさない
        let full = airController.isActive || recordingLabel != nil
        if full != fullRateRequested {
            fullRateRequested = full
            pipeline.setKeepFullRate(full)
        }

    }

    private func syncAir() {
        if air.mode != airController.state.mode || air.dragging != airController.state.dragging
            || air.pendingPinches != airController.state.pendingPinches
            || abs(air.volume - airController.state.volume) > 0.001 {
            air = airController.state
        }
    }

    private func handle(_ e: WristEvent) {
        switch e {
        case .flick(let d):
            let dir = settings.invertFlick ? -d : d
            if airController.flick(dir, t: ProcessInfo.processInfo.systemUptime) {
                syncAir()
            } else if !airController.isActive && dir < 0 {
                goBack()
            }
        default:
            break   // 手のひら・時計の動作は AirController が担当
        }
    }

    private func handle(_ o: PinchDetector.Output) {
        switch o {
        case .window(let w):
            guard let label = recordingLabel else { return }
            training.add(label, window: w)
            recordedThisRun += 1
            WKInterfaceDevice.current().play(.click)
        case .detected(let raw, let confidence):
            let label = GestureLabel(rawValue: raw) ?? .none
            lastGesture = "\(label.title) \(Int(confidence * 100))%"
            // 手首の衝撃からの推定は誤反応しやすいので、設定でオンにしたときだけ使う
            guard settings.wristPinch else { return }
            // 時計の方を向いていないときの衝撃（物を置いた等）は無視する
            guard recordingLabel == nil, confidence >= 0.6, reading.pose != .vertical else { return }
            // 安全装置: 腕を大きく振っている（歩く・走る）間の手首の衝撃は無視する
            if settings.blockWhileMoving && reading.gyro > 2.0 {
                if label == .pinch { flashPinch(.wrist, accepted: false) }
                return
            }
            if label == .pinch { pinch(from: .wrist) } else if label == .fist { back() }
        }
    }

    private func handleHead(_ e: HeadEvent) {
        guard settings.useHeadTracking else { return }
        lastGesture = e.title
        guard recordingLabel == nil else { return }
        e == .nod ? pinch(from: .nod) : back()
    }

    /// あらゆる経路のピンチ（手首の衝撃・ダブルタップ・アクセシビリティのクイックアクション・うなずき）
    func pinch(from source: PinchSource) {
        guard settings.gesturesEnabled else {
            flashPinch(source, accepted: false)
            return
        }
        airController.pinch(t: ProcessInfo.processInfo.systemUptime)
        syncAir()
        flashPinch(source, accepted: true)
    }

    /// 認識したピンチを画面に一瞬表示する（反応したかどうかを目で確かめられるように）
    private func flashPinch(_ source: PinchSource, accepted: Bool) {
        flashSequence += 1
        let flash = PinchFlash(id: flashSequence, accepted: accepted, source: source, count: air.pendingPinches)
        pinchFlash = flash
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if pinchFlash?.id == flash.id { pinchFlash = nil }
        }
    }

    /// Digital Crown で音量を変える（時計の状態）
    func crownVolume(_ v: Double) {
        airController.setVolume(v, t: ProcessInfo.processInfo.systemUptime)
        syncAir()
    }

    func back() {
        if airController.isActive {
            airController.cancel(t: ProcessInfo.processInfo.systemUptime)
            syncAir()
        } else {
            goBack()
        }
    }

    private func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
        WKInterfaceDevice.current().play(.directionDown)
    }

    // MARK: 時刻・音声

    func tellTime() {
        startTimeReadout()
        showToast(Date().formatted(date: .omitted, time: .shortened))
    }

    /// 手のひらを返したとき: 設定した秒数だけ待ってから時刻を伝える。待っている間に姿勢を崩せば取り消す
    private func startTimeReadoutAfterFlip() {
        readoutTask?.cancel()
        let delay = settings.timeDelay
        guard delay > 0 else {
            startTimeReadout()
            return
        }
        readoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.startTimeReadout()
        }
    }

    private func startTimeReadout() {
        let style = settings.timeStyle
        // 読み上げだけの設定でも、読み上げがオフ・音を出せないときは振動に切り替える
        if style.vibrates || !canUseSound || !settings.speechEnabled { teller.playHaptic(settings.hapticPattern) }
        if style.speaks { speak(TimeTeller.spoken()) }
    }

    private func stopTimeReadout() {
        readoutTask?.cancel()
        readoutTask = nil
        teller.stopHaptics()
        stopSpeaking()
    }

    /// 読み上げ: 出力先が Watch ならそのまま Watch のスピーカー。
    /// 自動なら iPhone → VoiceOver → Watch のスピーカー の順
    func speak(_ text: String) {
        guard canUseSound, settings.speechEnabled else { return }
        if settings.soundOutput == .watch {
            teller.speakLocally(text)
            return
        }
        if phone.speak(text) { return }
        if WKAccessibilityIsVoiceOverRunning() {
            AccessibilityNotification.Announcement(text).post()
            return
        }
        teller.speakLocally(text)
    }

    private func stopSpeaking() {
        phone.stopSpeech()
        teller.stopLocalSpeech()
    }

    private func pop() {
        WKInterfaceDevice.current().play(.click)
        guard canUseSound, settings.popSound else { return }
        if settings.soundOutput == .watch || !phone.pop() {
            TimeTeller.activateSpeaker()
            sfx.playPop()
        }
    }

    private func setSystemVolume(_ v: Double) {
        teller.speechVolume = Float(v)
        _ = phone.setVolume(v)
    }

    private func menuAction(_ a: MenuAction) {
        // 安全装置: AirPods を着けていないときは再生・曲送りをしない（スピーカーから突然鳴るのを防ぐ）
        if settings.mediaOnlyWithHeadphones && !phone.headphonesOn {
            WKInterfaceDevice.current().play(.failure)
            showToast(tr("イヤホンがありません", "No headphones"))
            return
        }
        if !phone.media(a) {
            WKInterfaceDevice.current().play(.failure)
            showToast(tr("iPhoneに接続できません", "Can't reach iPhone"))
        }
    }

    // MARK: 手のひらの校正

    /// 今の姿勢を「手のひらを見ている」基準として記録する
    func calibratePalm() -> Bool {
        guard let h = HeadState.shared.current(), reading.palmUp else { return false }
        palmCalibration = PalmCalibration(headPitch: h.pitch, headYaw: h.yaw,
                                          palmElevation: reading.palmElevation, palmAzimuth: reading.palmAzimuth,
                                          yawSign: palmCalibration?.yawSign ?? 1)
        return true
    }

    /// 手のひらを上に向けると画面が見えないので、音声（または振動）のカウントダウンで記録する
    func startPalmCalibration() {
        speak(trSpeech("3秒後に記録します。手のひらを上に向けて、手のひらを見てください",
                       "Recording in 3 seconds. Turn your palm up and look at it."))
        WKInterfaceDevice.current().play(.start)
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if HeadState.shared.current() == nil {
                WKInterfaceDevice.current().play(.failure)
                speak(trSpeech("AirPodsの向きが取れません", "Can't read the AirPods orientation"))
            } else if calibratePalm() {
                WKInterfaceDevice.current().play(.success)
                speak(trSpeech("記録しました", "Saved"))
            } else {
                WKInterfaceDevice.current().play(.failure)
                speak(trSpeech("手のひらが上を向いていません。もう一度どうぞ", "Your palm isn't facing up. Please try again."))
            }
        }
    }

    func toggleYawSign() {
        guard var c = palmCalibration else { return }
        c.yawSign = -c.yawSign
        palmCalibration = c
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == text { toast = nil }
        }
    }

    // MARK: 学習

    func startRecording(_ label: GestureLabel) {
        recordingLabel = label
        recordedThisRun = 0
        pipeline.configure { _, p, _ in p.mode = label == .none ? .recordFree : .recordOnset }
        WKInterfaceDevice.current().play(.start)
    }

    func stopRecording() {
        recordingLabel = nil
        pipeline.configure { _, p, _ in p.mode = .detect }
        training.commit()
        WKInterfaceDevice.current().play(.stop)
    }

    func exportTraining() {
        do {
            let url = try training.exportCSV()
            showToast(phone.send(file: url) ? tr("iPhoneへ送信中", "Sending to iPhone") : tr("iPhoneに接続できません", "Can't reach iPhone"))
        } catch {
            showToast(tr("書き出し失敗", "Export failed"))
        }
    }
}
