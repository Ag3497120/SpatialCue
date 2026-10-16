import Foundation

/// iPhone ⇄ Watch の WatchConnectivity メッセージのキー
enum WS {
    static let kind = "k"
    static let pitch = "p"
    static let yaw = "y"
    static let look = "l"
    static let event = "e"
    static let text = "x"
    static let connected = "c"
    static let interrupt = "i"
    static let volume = "v"
    static let media = "m"
    static let downSign = "d"
    static let worn = "w"
    static let settings = "settings"
    static let command = "cmd"
    static let palmCalibrated = "pc"
    static let residency = "res"
    static let lang = "lang"

    enum Kind: String {
        case headPose    // 頭の角度（iPhone → Watch）
        case headEvent   // うなずき・首振り（iPhone → Watch）
        case headStatus  // AirPods 接続状態（iPhone → Watch）
        case speak       // 読み上げ依頼（Watch → iPhone）
        case stopSpeech  // 読み上げ停止（Watch → iPhone）
        case pop         // 「ポン」の効果音（Watch → iPhone）
        case setVolume   // システム音量（Watch → iPhone）
        case media       // メニュー操作: 再生／停止・曲送り（Watch → iPhone）
        case settings    // 設定（iPhone → Watch）
        case command     // 校正などの操作依頼（iPhone → Watch）
        case watchStatus // 手のひら校正の有無・常駐状態（Watch → iPhone）
    }
}

enum HeadEvent: String {
    case nod, shake

    var title: String { self == .nod ? tr("うなずき", "Nod") : tr("首振り", "Shake") }
}

/// 仮想メニューの操作（ピンチ回数で選ぶ）
enum MenuAction: String {
    case playPause, nextTrack, previousTrack

    /// 読み上げ用の名前
    var spokenTitle: String {
        switch self {
        case .playPause: return trSpeech("再生・停止", "Play, pause")
        case .nextTrack: return trSpeech("次の曲", "Next track")
        case .previousTrack: return trSpeech("前の曲", "Previous track")
        }
    }

    var title: String {
        switch self {
        case .playPause: return tr("再生・停止", "Play/Pause")
        case .nextTrack: return tr("次の曲", "Next track")
        case .previousTrack: return tr("前の曲", "Previous track")
        }
    }
}

struct Vec3: Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vec3(x: 0, y: 0, z: 0)

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: Vec3, k: Double) -> Vec3 { Vec3(x: a.x * k, y: a.y * k, z: a.z * k) }
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

/// 角度差を -180…180 に収める
func wrapDegrees(_ a: Double) -> Double {
    var x = a.truncatingRemainder(dividingBy: 360)
    if x > 180 { x -= 360 } else if x < -180 { x += 360 }
    return x
}
