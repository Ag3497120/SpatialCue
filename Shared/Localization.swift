import Foundation

/// 対応言語
enum Lang: String, Codable {
    case ja, en

    /// 読み上げの声
    var voiceCode: String { self == .ja ? "ja-JP" : "en-US" }

    static var device: Lang {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ja") ? .ja : .en
    }
}

/// 画面の言語の選択肢
enum LanguageChoice: String, Codable, CaseIterable, Identifiable {
    case system, ja, en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return tr("端末に合わせる", "Match device")
        case .ja: return "日本語"
        case .en: return "English"
        }
    }

    var resolved: Lang {
        switch self {
        case .system: return .device
        case .ja: return .ja
        case .en: return .en
        }
    }
}

/// 読み上げの言語の選択肢
enum SpeechLanguageChoice: String, Codable, CaseIterable, Identifiable {
    case app, ja, en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return tr("画面の言語に合わせる", "Same as app")
        case .ja: return "日本語"
        case .en: return "English"
        }
    }
}

/// 現在の言語。設定が変わったら `L10n.apply(_:)` で更新する
enum L10n {
    static var ui = Lang.device
    static var speech = Lang.device

    static func apply(app: LanguageChoice, speech s: SpeechLanguageChoice) {
        ui = app.resolved
        switch s {
        case .app: speech = ui
        case .ja: speech = .ja
        case .en: speech = .en
        }
    }
}

/// 画面に出す文字列
func tr(_ ja: String, _ en: String) -> String { L10n.ui == .ja ? ja : en }

/// 読み上げる文字列
func trSpeech(_ ja: String, _ en: String) -> String { L10n.speech == .ja ? ja : en }
