import AVFoundation
import CoreMotion
import Foundation
import MediaPlayer
import UIKit
import WatchConnectivity

/// AirPods の頭の向きを読んで Apple Watch に中継し、設定を同期し、
/// Watch からの読み上げ・効果音・音量・再生操作の依頼を実行する。
@MainActor
final class PhoneHub: NSObject, ObservableObject {
    static let calibrationKey = "phoneHeadCalibration"

    @Published private(set) var airPodsConnected = false
    /// 音声出力が AirPods（＝耳に着けている。外すと自動でスピーカーに切り替わる）
    @Published private(set) var airPodsWorn = false
    @Published private(set) var outputName = "—"
    @Published private(set) var motionAvailable = false
    @Published private(set) var authorization = "—"
    @Published private(set) var watchPaired = false
    @Published private(set) var watchAppInstalled = false
    @Published private(set) var watchReachable = false
    @Published private(set) var watchPalmCalibrated = false
    @Published private(set) var watchResidency = "—"
    @Published private(set) var lastEvent = "—"
    @Published private(set) var exports: [URL] = []
    @Published private(set) var lastCommand = "—"
    @Published var calibration = HeadCalibration.load(key: PhoneHub.calibrationKey) {
        didSet { calibration.save(key: Self.calibrationKey) }
    }
    @Published var keepAliveInBackground = !Edition.isStable && UserDefaults.standard.bool(forKey: "keepAlive") {
        didSet {
            UserDefaults.standard.set(keepAliveInBackground, forKey: "keepAlive")
            updateKeepAlive()
        }
    }
    /// Watch と共有する設定。変えるとすぐ Watch に送る
    @Published var settings: WristSettings = {
        let s = WristSettings.load()
        s.applyLanguage()
        return s
    }() {
        didSet {
            guard settings != oldValue else { return }
            settings.applyLanguage()
            settings.save()
            pushSettings()
        }
    }

    /// 頭の向きの表示用。頻繁に変わるので設定画面全体を描き直さないよう別オブジェクトにする
    let live = HeadLive()
    private(set) var pitch = 0.0
    private(set) var yaw = 0.0
    private(set) var look = 0.0
    private var lastLiveUpdate: TimeInterval = 0

    private let headphones = CMHeadphoneMotionManager()
    private let gestures = HeadGestureDetector()
    private let speech = AVSpeechSynthesizer()
    private let silence = SilentAudio()
    private let sfx = SoundFX()
    /// 画面に置いた非表示の MPVolumeView のスライダー。これを動かすとシステム音量が変わる
    weak var volumeSlider: UISlider?
    private var lastSend: TimeInterval = 0
    private var started = false
    /// 音声の割り込みで他のアプリを一時停止させている
    private var pausedOthers = false

    var mediaRemoteAvailable: Bool { MediaRemote.isAvailable }

    /// 音を出してよいか（安全装置: AirPods が無いときは iPhone のスピーカーから鳴らさない）
    private var canUseSound: Bool { airPodsWorn || !settings.vibrationOnlyWithoutAirPods }

    nonisolated static var exportsDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() {
        guard !started else { return }
        started = true
        useMixableSession()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRoute() }
        }
        refreshRoute()
        if WCSession.isSupported() {
            let s = WCSession.default
            s.delegate = self
            s.activate()
        }
        headphones.delegate = self
        motionAvailable = headphones.isDeviceMotionAvailable
        refreshAuthorization()
        if motionAvailable {
            headphones.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
                guard let m else { return }
                MainActor.assumeIsolated { self?.handle(m) }
            }
        }
        if MPMediaLibrary.authorizationStatus() == .notDetermined { MPMediaLibrary.requestAuthorization { _ in } }
        refreshExports()
        updateKeepAlive()
    }

    private func refreshAuthorization() {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .authorized: authorization = tr("許可済み", "Allowed")
        case .denied: authorization = tr("拒否（設定アプリで許可）", "Denied (allow in Settings)")
        case .restricted: authorization = tr("制限あり", "Restricted")
        case .notDetermined: authorization = tr("未確認", "Not asked yet")
        @unknown default: authorization = tr("不明", "Unknown")
        }
    }

    /// 出力先が Bluetooth の AirPods（Beats 含む）なら「装着中」。
    /// AirPods は耳から外すと自動で出力がスピーカーに戻るので、これで装着を判定できる
    private func refreshRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        outputName = outputs.first?.portName ?? "—"
        let bluetooth: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        let worn = outputs.contains { out in
            bluetooth.contains(out.portType)
                && (out.portName.localizedCaseInsensitiveContains("AirPods")
                    || out.portName.localizedCaseInsensitiveContains("Beats")
                    || airPodsConnected)
        }
        if worn != airPodsWorn {
            airPodsWorn = worn
            if !worn { speech.stopSpeaking(at: .immediate) }
            sendStatus()
        }
    }

    private func handle(_ m: CMDeviceMotion) {
        pitch = m.attitude.pitch * 180 / .pi
        yaw = m.attitude.yaw * 180 / .pi
        look = calibration.lookAmount(pitch: pitch)
        if m.timestamp - lastLiveUpdate >= 0.1 {
            lastLiveUpdate = m.timestamp
            live.update(pitch: pitch, yaw: yaw, look: look)
        }
        if let e = gestures.feed(t: m.timestamp, pitch: pitch, yaw: yaw) {
            lastEvent = e.title
            send([WS.kind: WS.Kind.headEvent.rawValue, WS.event: e.rawValue])
        }
        if m.timestamp - lastSend >= 1.0 / 15 {
            lastSend = m.timestamp
            send([WS.kind: WS.Kind.headPose.rawValue, WS.pitch: pitch, WS.yaw: yaw, WS.look: look,
                  WS.downSign: calibration.downSign])
        }
    }

    private func send(_ message: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable else { return }
        s.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    private func sendStatus() {
        send([WS.kind: WS.Kind.headStatus.rawValue, WS.connected: airPodsConnected, WS.worn: airPodsWorn,
              WS.volume: Double(AVAudioSession.sharedInstance().outputVolume)])
    }

    // MARK: 設定と Watch への依頼

    /// applicationContext は Watch が離れていても次につながったときに届く
    private func pushSettings() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = settings.encoded() else { return }
        try? WCSession.default.updateApplicationContext([WS.settings: data])
        send([WS.kind: WS.Kind.settings.rawValue, WS.settings: data])
    }

    func sendCommand(_ c: WatchCommand) {
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            lastCommand = tr("Watch に接続できません", "Can't reach Watch")
            return
        }
        send([WS.kind: WS.Kind.command.rawValue, WS.command: c.rawValue])
        lastCommand = tr("Watch へ: \(c.rawValue)", "Sent to Watch: \(c.rawValue)")
    }

    func captureNeutral() { calibration.neutralPitch = pitch }

    func captureLook() {
        calibration.lookPitch = pitch
        calibration.calibrated = true
    }

    // MARK: 音

    private func useMixableSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
    }

    func speak(_ text: String, interrupt: Bool = true, lang: Lang? = nil) {
        guard canUseSound, settings.speechEnabled else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: (lang ?? L10n.speech).voiceCode)
        try? AVAudioSession.sharedInstance().setActive(true)
        if interrupt { speech.stopSpeaking(at: .immediate) }
        speech.speak(u)
    }

    func stopSpeaking() { speech.stopSpeaking(at: .immediate) }

    func pop() {
        guard canUseSound else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        sfx.playPop()
    }

    func setSystemVolume(_ v: Double) {
        let value = clamp(v, 0, settings.maxVolume)
        guard let slider = volumeSlider else { lastCommand = tr("音量: スライダー未準備", "Volume: slider not ready"); return }
        slider.value = Float(value)
        slider.sendActions(for: .valueChanged)
        lastCommand = tr("音量 \(Int(value * 100))%", "Volume \(Int(value * 100))%")
    }

    // MARK: 再生中の曲の操作

    func perform(_ a: MenuAction) {
        // 安全装置: AirPods を着けていないときは操作しない（iPhone のスピーカーから突然鳴るのを防ぐ）
        if settings.mediaOnlyWithAirPods && !airPodsWorn {
            lastCommand = tr("\(a.title): AirPods 未装着のため無視", "\(a.title): ignored, AirPods not worn")
            return
        }
        let music = MPMusicPlayerController.systemMusicPlayer
        let musicPlaying = music.playbackState == .playing
        let otherPlaying = AVAudioSession.sharedInstance().isOtherAudioPlaying && !musicPlaying

        switch a {
        case .playPause:
            if musicPlaying {
                music.pause()
                lastCommand = tr("停止（ミュージック）", "Paused (Music)")
            } else if otherPlaying {
                pauseOtherApp()
            } else if pausedOthers {
                resumeOtherApp()
            } else if settings.experimentalMediaRemote && MediaRemote.send(.play) {
                lastCommand = tr("再生（MediaRemote）", "Play (MediaRemote)")
                // 何も鳴り出さなければミュージックの続きを再生
                Task {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    if !AVAudioSession.sharedInstance().isOtherAudioPlaying, music.nowPlayingItem != nil {
                        music.play()
                        lastCommand = tr("再生（ミュージック）", "Play (Music)")
                    }
                }
            } else if music.nowPlayingItem != nil {
                music.play()
                lastCommand = tr("再生（ミュージック）", "Play (Music)")
            } else {
                lastCommand = tr("再生できる曲がありません", "Nothing to play")
                speak(trSpeech("再生できる曲がありません", "Nothing to play"))
            }
        case .nextTrack, .previousTrack:
            let next = a == .nextTrack
            if musicPlaying || (!otherPlaying && music.nowPlayingItem != nil) {
                next ? music.skipToNextItem() : music.skipToPreviousItem()
                lastCommand = tr("\(a.title)（ミュージック）", "\(a.title) (Music)")
            } else if settings.experimentalMediaRemote && MediaRemote.send(next ? .nextTrack : .previousTrack) {
                lastCommand = "\(a.title) (MediaRemote)"
            } else {
                lastCommand = tr("\(a.title): ミュージック以外は「他のアプリも操作」が必要",
                                 "\(a.title): turn on \"Control other apps\" for apps other than Music")
                speak(trSpeech("ミュージック以外のアプリの曲送りには、iPhoneの設定で、他のアプリも操作、をオンにしてください",
                               "To skip tracks in apps other than Music, turn on Control other apps in the iPhone settings"))
            }
        }
    }

    /// 他のアプリを止める: まず MediaRemote、効かなければ音声の割り込み
    private func pauseOtherApp() {
        if settings.experimentalMediaRemote && MediaRemote.send(.pause) {
            lastCommand = tr("停止（MediaRemote）", "Paused (MediaRemote)")
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if AVAudioSession.sharedInstance().isOtherAudioPlaying { interruptOthers() }
            }
        } else {
            interruptOthers()
        }
    }

    /// 他と混ざらない音声セッションを有効にすると、再生中のアプリは割り込みを受けて一時停止する
    private func interruptOthers() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            pausedOthers = true
            lastCommand = tr("停止（割り込み）", "Paused (interruption)")
        } catch {
            lastCommand = tr("停止できませんでした", "Couldn't pause")
        }
    }

    /// 割り込みを解除すると、対応しているアプリは自動で再開する
    private func resumeOtherApp() {
        silence.stop()
        sfx.stop()
        speech.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        pausedOthers = false
        useMixableSession()
        updateKeepAlive()
        lastCommand = tr("再開（割り込み解除）", "Resumed (interruption ended)")
    }

    // MARK: 学習データ

    func refreshExports() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.exportsDirectory, includingPropertiesForKeys: nil)) ?? []
        exports = urls.filter { $0.pathExtension == "csv" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func deleteExports(at offsets: IndexSet) {
        for i in offsets { try? FileManager.default.removeItem(at: exports[i]) }
        refreshExports()
    }

    private func updateKeepAlive() {
        keepAliveInBackground && !Edition.isStable ? silence.start() : silence.stop()
    }

    private func refreshWatchState(_ s: WCSession) {
        watchPaired = s.isPaired
        watchAppInstalled = s.isWatchAppInstalled
        watchReachable = s.isReachable
    }
}

extension PhoneHub: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.airPodsConnected = true
            self.refreshAuthorization()
            self.refreshRoute()
            self.sendStatus()
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.airPodsConnected = false
            self.refreshRoute()
            self.sendStatus()
        }
    }
}

extension PhoneHub: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.refreshWatchState(session)
            self.pushSettings()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()   // Watch を切り替えたとき
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshWatchState(session) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshWatchState(session)
            self.sendStatus()
            if session.isReachable { self.pushSettings() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let kind = (message[WS.kind] as? String).flatMap(WS.Kind.init) else { return }
        switch kind {
        case .speak:
            guard let text = message[WS.text] as? String else { return }
            let interrupt = message[WS.interrupt] as? Bool ?? true
            let lang = (message[WS.lang] as? String).flatMap(Lang.init)
            Task { @MainActor in self.speak(text, interrupt: interrupt, lang: lang) }
        case .stopSpeech:
            Task { @MainActor in self.stopSpeaking() }
        case .pop:
            Task { @MainActor in self.pop() }
        case .setVolume:
            guard let v = message[WS.volume] as? Double else { return }
            Task { @MainActor in self.setSystemVolume(v) }
        case .media:
            guard let a = (message[WS.media] as? String).flatMap(MenuAction.init) else { return }
            Task { @MainActor in self.perform(a) }
        case .watchStatus:
            let palm = message[WS.palmCalibrated] as? Bool ?? false
            let res = message[WS.residency] as? String ?? "—"
            Task { @MainActor in
                self.watchPalmCalibrated = palm
                self.watchResidency = res
            }
        case .headPose, .headEvent, .headStatus, .settings, .command:
            break
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // このメソッドから戻るとファイルは消されるので、ここで移動する
        let name = file.fileURL.lastPathComponent
        let dest = PhoneHub.exportsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: file.fileURL, to: dest)
        Task { @MainActor in self.refreshExports() }
    }
}

/// 頭の向きの表示用（1 秒 10 回まで更新）
@MainActor
final class HeadLive: ObservableObject {
    @Published private(set) var pitch = 0.0
    @Published private(set) var yaw = 0.0
    @Published private(set) var look = 0.0

    func update(pitch: Double, yaw: Double, look: Double) {
        self.pitch = pitch
        self.yaw = yaw
        self.look = look
    }
}

/// 画面ロック中もアプリを動かし続けるための無音再生
final class SilentAudio {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var running = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard !running, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else { return }
        buffer.frameLength = buffer.frameCapacity
        if let ch = buffer.floatChannelData {
            for c in 0..<Int(format.channelCount) { ch[c].update(repeating: 0, count: Int(buffer.frameLength)) }
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        running = true
    }

    func stop() {
        guard running else { return }
        player.stop()
        engine.stop()
        running = false
    }
}
