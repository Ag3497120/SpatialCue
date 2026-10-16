import Foundation
import WatchConnectivity

/// iPhone アプリとの通信。AirPods の頭の向き・装着状態・設定を受け取り、読み上げ・効果音・音量・曲送りを依頼する。
@MainActor
final class PhoneLink: NSObject, ObservableObject {
    @Published private(set) var reachable = false
    @Published private(set) var phoneAirPods = false
    /// iPhone の音声出力がイヤホンになっている
    @Published private(set) var headphonesOn = false

    var onHeadEvent: ((HeadEvent) -> Void)?
    var onSystemVolume: ((Double) -> Void)?
    var onSettings: ((WristSettings) -> Void)?
    var onCommand: ((WatchCommand) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// iPhone（＝AirPods）で読み上げる。届かなければ false
    func speak(_ text: String, interrupt: Bool = true) -> Bool {
        send([WS.kind: WS.Kind.speak.rawValue, WS.text: text, WS.interrupt: interrupt, WS.lang: L10n.speech.rawValue])
    }

    func stopSpeech() { _ = send([WS.kind: WS.Kind.stopSpeech.rawValue]) }

    func pop() -> Bool { send([WS.kind: WS.Kind.pop.rawValue]) }

    func setVolume(_ v: Double) -> Bool { send([WS.kind: WS.Kind.setVolume.rawValue, WS.volume: v]) }

    func media(_ a: MenuAction) -> Bool { send([WS.kind: WS.Kind.media.rawValue, WS.media: a.rawValue]) }

    func sendStatus(palmCalibrated: Bool, residency: String) {
        _ = send([WS.kind: WS.Kind.watchStatus.rawValue, WS.palmCalibrated: palmCalibrated, WS.residency: residency])
    }

    func send(file: URL) -> Bool {
        let s = WCSession.default
        guard WCSession.isSupported(), s.activationState == .activated else { return false }
        s.transferFile(file, metadata: ["kind": "gestures"])
        return true
    }

    private func send(_ message: [String: Any]) -> Bool {
        let s = WCSession.default
        guard WCSession.isSupported(), s.activationState == .activated, s.isReachable else { return false }
        s.sendMessage(message, replyHandler: nil, errorHandler: nil)
        return true
    }

    nonisolated private func applySettings(from dict: [String: Any]) {
        guard let s = WristSettings.decode(dict[WS.settings] as? Data) else { return }
        Task { @MainActor in self.onSettings?(s) }
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let r = session.isReachable
        applySettings(from: session.receivedApplicationContext)
        Task { @MainActor in self.reachable = r }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in
            self.reachable = r
            if !r {
                self.phoneAirPods = false
                self.headphonesOn = false   // iPhone と離れたらイヤホンは無いものとして扱う（安全側）
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applySettings(from: applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let kind = (message[WS.kind] as? String).flatMap(WS.Kind.init) else { return }
        switch kind {
        case .headPose:
            guard let p = message[WS.pitch] as? Double, let y = message[WS.yaw] as? Double,
                  let l = message[WS.look] as? Double else { return }
            let d = message[WS.downSign] as? Double ?? -1
            HeadState.shared.update(.init(pitch: p, yaw: y, look: l, downSign: d, source: .phone, time: Date()))
        case .headEvent:
            guard let e = (message[WS.event] as? String).flatMap(HeadEvent.init) else { return }
            Task { @MainActor in self.onHeadEvent?(e) }
        case .headStatus:
            let c = message[WS.connected] as? Bool ?? false
            let w = message[WS.worn] as? Bool ?? false
            let v = message[WS.volume] as? Double
            Task { @MainActor in
                self.phoneAirPods = c
                self.headphonesOn = w
                if let v { self.onSystemVolume?(v) }
            }
        case .settings:
            applySettings(from: message)
        case .command:
            guard let c = (message[WS.command] as? String).flatMap(WatchCommand.init) else { return }
            Task { @MainActor in self.onCommand?(c) }
        case .speak, .stopSpeech, .pop, .setVolume, .media, .watchStatus:
            break
        }
    }
}
