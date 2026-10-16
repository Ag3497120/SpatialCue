import AVFoundation
import WatchKit

/// 振動と音声で時刻を伝える。1 回再生したら終わり。どちらも 24 時間制。
///
/// 数字通り: 十の位 = 長いタップの回数、一の位 = 短いタップの回数（時 → 休み → 分）。0 の桁は鳴らさない。
///
/// モールス信号: 「時・分」の各桁をモールス符号で送る。
/// - 十の位（大きい桁）は強い振動、一の位（小さい桁）は弱い振動
/// - 短点 = 1 回、長点 = 3 回の連打。桁の間は少し、時と分の間は長めにあける
/// - 時の十の位が 0 のときは省略
@MainActor
final class TimeTeller {
    var speechVolume: Float = 1
    private var task: Task<Void, Never>?
    private let synth = AVSpeechSynthesizer()

    static let morseDigits = ["-----", ".----", "..---", "...--", "....-", ".....", "-....", "--...", "---..", "----."]

    /// 「10時42分です」/ "It's 10:42"
    static func spoken(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return trSpeech("\(h)時\(m)分です", String(format: "It's %d:%02d", h, m))
    }

    /// Watch のスピーカーで鳴らせるように音声セッションを有効にする
    static func activateSpeaker() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [])
        try? session.setActive(true)
    }

    func speakLocally(_ text: String) {
        Self.activateSpeaker()
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: L10n.speech.voiceCode)
        u.volume = speechVolume
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }

    func stopLocalSpeech() { synth.stopSpeaking(at: .immediate) }

    func stopHaptics() {
        task?.cancel()
        task = nil
    }

    func playHaptic(_ pattern: HapticPattern, date d: Date = Date()) {
        play(pattern == .digits ? Self.digitsSequence(d) : Self.morseSequence(d))
    }

    /// (振動の種類, 次までの秒数)。種類が nil なら休み
    typealias Step = (WKHapticType?, Double)

    /// Apple Watch の Taptic タイム「数字通り」に近づけた振動。
    /// 長いタップ = 一続きの強い振動（notification）、短いタップ = 軽いクリック。
    /// 時は Watch の 12／24 時間制の設定に合わせる。0 の桁は鳴らさない。
    /// （watchOS では Core Haptics が使えないので、用意された振動の種類で近づけている）
    static func digitsSequence(_ d: Date) -> [Step] {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        var h = c.hour ?? 0
        let m = c.minute ?? 0
        if !uses24Hour {
            h %= 12
            if h == 0 { h = 12 }
        }
        var seq: [Step] = []
        func long(_ n: Int) {
            for _ in 0..<n { seq.append((.notification, 0.85)) }
        }
        func short(_ n: Int) {
            for _ in 0..<n { seq.append((.click, 0.32)) }
        }
        long(h / 10); short(h % 10)
        seq.append((nil, 0.8))
        long(m / 10); short(m % 10)
        return seq
    }

    /// 端末の時刻表示が 24 時間制か
    static var uses24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "H"
        return format.contains("H") || format.contains("k")
    }

    static func morseSequence(_ d: Date) -> [Step] {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0
        let unit = 0.2
        var seq: [Step] = []
        func digit(_ n: Int, strong: Bool) {
            let tap: WKHapticType = strong ? .start : .click
            for symbol in morseDigits[n] {
                if symbol == "." {
                    seq.append((tap, unit * 1.5))
                } else {
                    seq.append((tap, 0.07)); seq.append((tap, 0.07)); seq.append((tap, unit * 1.5))
                }
            }
            seq.append((nil, unit * 2.5))
        }
        if h >= 10 { digit(h / 10, strong: true) }
        digit(h % 10, strong: false)
        seq.append((nil, unit * 4))
        digit(m / 10, strong: true)
        digit(m % 10, strong: false)
        return seq
    }

    private func play(_ seq: [Step]) {
        task?.cancel()
        task = Task {
            for (type, wait) in seq {
                if Task.isCancelled { return }
                if let type { WKInterfaceDevice.current().play(type) }
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }
}
