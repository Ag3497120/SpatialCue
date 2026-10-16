import Foundation

/// 時刻の伝え方
enum TimeAnnounceStyle: String, CaseIterable, Identifiable, Codable {
    case vibration = "morse"   // 以前の保存値と互換
    case voice, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibration: return tr("振動", "Vibration")
        case .voice: return tr("読み上げ", "Voice")
        case .both: return tr("両方", "Both")
        }
    }

    var vibrates: Bool { self != .voice }
    var speaks: Bool { self != .vibration }
}

/// 振動のパターン（Apple Watch の Taptic タイムに合わせた名前）
enum HapticPattern: String, CaseIterable, Identifiable, Codable {
    case digits, morse

    var id: String { rawValue }

    var title: String { self == .digits ? tr("数字通り", "Digits") : tr("モールス信号", "Morse code") }

    var explanation: String {
        switch self {
        case .digits:
            return tr("10時間単位で長いタップ、続けて1時間単位で短いタップ。そのあと10分単位で長いタップ、1分単位で短いタップ。",
                      "A long tap for every 10 hours, then a short tap for every hour. Then a long tap for every 10 minutes and a short tap for every minute.")
        case .morse:
            return tr("時・分の各桁をモールス符号で。十の位は強い振動、一の位は弱い振動。短点 = 1回、長点 = 3連打。",
                      "Each digit of the hour and minute in Morse code. Tens are strong taps, ones are light taps. Dot = 1 tap, dash = 3 quick taps.")
        }
    }
}

enum WristSetup: String, CaseIterable, Identifiable, Codable {
    case auto, crownTowardHand, crownTowardElbow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return tr("自動", "Automatic")
        case .crownTowardHand: return tr("竜頭が手の側", "Crown toward hand")
        case .crownTowardElbow: return tr("竜頭が肘の側", "Crown toward elbow")
        }
    }
}

/// すべての設定。iPhone アプリで編集し、Watch に同期する。
struct WristSettings: Codable, Equatable {
    // 言語
    var appLanguage = LanguageChoice.system
    var speechLanguage = SpeechLanguageChoice.app

    // ジェスチャー
    var gesturesEnabled = true          // 全体のオン／オフ（緊急停止）
    var requireHeadLook = false
    var headLookThreshold = 0.5
    var wristPinch = false              // 手首の衝撃からピンチを推定する（実験・誤反応しやすい）
    var pinchSensitivity = 0.5
    var flickSensitivity = 0.5
    var invertVolumeX = false
    var invertFlick = false
    var wristSetup = WristSetup.auto
    var gazeThreshold = 25.0

    // 読み上げ
    var speechEnabled = true            // オフにすると読み上げを一切しない（効果音と振動は残る）

    // 時刻
    var timeStyle = TimeAnnounceStyle.both
    var hapticPattern = HapticPattern.morse

    // 常駐
    var workoutMode = false
    var keepRunning = true
    var powerSaving = true

    // メディア
    var directMedia = true                   // メニューを省略し、時計でピンチ回数から直接操作する

    // 安全装置
    var mediaOnlyWithAirPods = true          // AirPods を着けているときだけ再生・曲送り
    var vibrationOnlyWithoutAirPods = true   // AirPods が無いときは音を出さず振動だけ
    var maxVolume = 0.8                      // 音量スライダーの上限
    var blockWhileMoving = true              // 腕を大きく動かしている間の手首ピンチを無視
    var experimentalMediaRemote = true       // ミュージック以外のアプリも操作する（非公開 API・実験）

    static let storageKey = "wristSettings"

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// 保存済みの値を既定値に重ねて読む（新しい項目が増えても古いデータを読める）
    static func decode(_ data: Data?) -> WristSettings? {
        guard let data,
              let stored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defaultsData = WristSettings().encoded(),
              var merged = (try? JSONSerialization.jsonObject(with: defaultsData)) as? [String: Any] else { return nil }
        merged.merge(stored) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(WristSettings.self, from: mergedData)
    }

    /// 言語の設定を反映する
    func applyLanguage() { L10n.apply(app: appLanguage, speech: speechLanguage) }

    static func load() -> WristSettings {
        decode(UserDefaults.standard.data(forKey: storageKey)) ?? WristSettings()
    }

    func save() {
        if let d = encoded() { UserDefaults.standard.set(d, forKey: Self.storageKey) }
    }
}

/// iPhone から Watch への操作依頼
enum WatchCommand: String {
    case calibratePalm, flipPalmYaw, clearPalm, testTime
}
