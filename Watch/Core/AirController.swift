import Foundation

/// 画面を見ずに音と振動で操作する「仮想ウィンドウ」
enum AirMode: String {
    case idle, ready, clock, volume, menu

    var title: String {
        switch self {
        case .idle: return ""
        case .ready: return tr("準備完了", "Ready")
        case .clock: return tr("時計", "Clock")
        case .volume: return tr("音量", "Volume")
        case .menu: return tr("メニュー", "Menu")
        }
    }
}

/// 読み上げる内容。文言は言語に応じて `text` で作る
enum AirPhrase: Equatable {
    case closed, menuClosed, menuOpened
    case menuAction(MenuAction)
    case volume(Int)     // 「音量 40%」
    case percent(Int)    // 「50%」

    var text: String {
        switch self {
        case .closed: return trSpeech("閉じました", "Closed")
        case .menuClosed: return trSpeech("メニューを閉じました", "Menu closed")
        case .menuOpened: return trSpeech("メニュー。1回 再生、2回 次、3回 前",
                                          "Menu. One, play. Two, next. Three, previous")
        case .menuAction(let a): return a.spokenTitle
        case .volume(let v): return trSpeech("音量 \(v)%", "Volume \(v) percent")
        case .percent(let v): return trSpeech("\(v)%", "\(v) percent")
        }
    }
}

/// 仮想 UI の状態機械。
///
/// 手のひらを上に向けている間は画面が見えないので、操作は時刻とメディアに絞る。
/// - 手のひらを見る → 「ポン」で準備完了（ここでのピンチは何もしない）
/// - 手のひら → 表へ素早く返す → 時計（読み上げ＋振動）。姿勢を崩すと止まる
/// - 時計（メニュー省略・既定）: ダブルタップ（ピンチ）= 再生／停止、右に払う = 次の曲、左に払う = 前の曲、竜頭 = 音量
/// - 時計（メニューを使う設定）: ピンチして動かす → 音量スライダー。ピンチ 1 回 → メニュー
/// - メニュー: ピンチ 1 回 = 再生／停止、2 回 = 次の曲、3 回以上 = 前の曲
///
/// ピンチの後 0.6 秒以内に手首が動けば「ピンチして動かす」、動かずに次のピンチも来なければ回数を確定する。
final class AirController {
    struct Effects {
        var speak: (AirPhrase) -> Void = { _ in }
        var stopSpeaking: () -> Void = {}
        var pop: () -> Void = {}
        var tick: () -> Void = {}
        var startTimeReadout: () -> Void = {}
        var stopTimeReadout: () -> Void = {}
        var setVolume: (Double) -> Void = { _ in }
        var menu: (MenuAction) -> Void = { _ in }
    }

    struct Config {
        var invertX = false
        var tapWindow = 0.6        // ピンチ回数を確定するまでの待ち時間
        var menuTapWindow = 0.9    // メニューでは回数を数えるので長めに待つ
        var directMedia = true     // メニューを省略し、時計の状態で直接操作する（ピンチ = 再生・停止、払う = 曲送り・曲戻し、竜頭 = 音量）
        var moveThreshold = 6.0    // ピンチ後にこれ以上（度）動いたらドラッグ
        var stillTime = 0.8        // ドラッグ中にこれだけ止まったら確定
        var menuTimeout = 15.0     // 最後の操作からこれだけ何もなければメニューを閉じる
        var maxVolume = 1.0        // 安全装置: 音量スライダーの上限
    }

    struct State {
        var mode = AirMode.idle
        var volume = 0.5
        var dragging = false
        var pendingPinches = 0
    }

    var effects = Effects()
    var config = Config()
    private(set) var state = State()

    var mode: AirMode { state.mode }
    var isActive: Bool { state.mode != .idle }

    private var pending: (count: Int, last: TimeInterval, roll: Double, elev: Double)?
    private var anchor = (roll: 0.0, elev: 0.0, volume: 0.0)
    private var lastMove: TimeInterval = 0
    private var reading = WristReading()
    private var spokenVolumeStep = -1
    private var lastVolumeSent: TimeInterval = -10
    private var modeSince: TimeInterval = 0

    /// iPhone から現在のシステム音量が届いたとき
    func syncVolume(_ v: Double) {
        if !state.dragging { state.volume = clamp(v, 0, 1) }
    }

    // MARK: 入力

    func wrist(_ e: WristEvent, t: TimeInterval) {
        switch e {
        case .palmGazeBegan:
            guard state.mode != .ready else { return }
            if state.mode != .idle { effects.stopTimeReadout() }
            enter(.ready, t: t)
            effects.pop()
        case .palmUpEnded:
            if state.mode == .ready { enter(.idle, t: t) }
        case .flipToFace:
            enter(.clock, t: t)
            effects.startTimeReadout()
        case .glanceEnded:
            if [.clock, .volume, .menu].contains(state.mode) {
                if state.dragging { effects.setVolume(state.volume) }
                effects.stopTimeReadout()
                enter(.idle, t: t)
            }
        case .glanceBegan, .palmUpBegan, .palmGazeEnded, .flick:
            break
        }
    }

    /// ピンチ（手首の衝撃・ダブルタップ・アクセシビリティのクイックアクション）。処理したら true
    @discardableResult
    func pinch(t: TimeInterval) -> Bool {
        switch state.mode {
        case .idle:
            return false
        case .ready:
            break   // 画面が見えない姿勢なので何もしない（誤操作で画面側が動かないよう消費だけする）
        case .clock where config.directMedia && !state.dragging:
            // ダブルタップ（ピンチ）1 回 = 再生・停止。回数を数えないので待たずにすぐ実行する
            runMedia(.playPause, t: t)
            effects.tick()
        case .clock, .volume, .menu:
            if state.dragging {
                endDrag(t: t)
            } else if var p = pending {
                p.count += 1
                p.last = t
                pending = p
            } else {
                pending = (1, t, reading.roll, reading.elevation)
                // メニューの説明を聞き終わるのを待たずに操作できるよう、読み上げを止める
                if state.mode == .menu { effects.stopSpeaking() }
            }
            state.pendingPinches = pending?.count ?? 0
            modeSince = t
            effects.tick()
        }
        return true
    }

    /// 手首を払う（+1 = 右、-1 = 左）。時計の状態では曲送り・曲戻し。処理したら true
    @discardableResult
    func flick(_ direction: Int, t: TimeInterval) -> Bool {
        guard config.directMedia, state.mode == .clock || state.mode == .volume, !state.dragging else { return false }
        runMedia(direction > 0 ? .nextTrack : .previousTrack, t: t)
        effects.tick()
        return true
    }

    /// Digital Crown などで音量を直接決める
    func setVolume(_ v: Double, t: TimeInterval) {
        guard isActive else { return }
        if state.mode != .volume { effects.stopTimeReadout() }
        state.volume = clamp(v, 0, config.maxVolume)
        let step = Int((state.volume * 10).rounded())
        if step != spokenVolumeStep {
            spokenVolumeStep = step
            effects.speak(.percent(step * 10))
        }
        if t - lastVolumeSent > 0.2 {
            lastVolumeSent = t
            effects.setVolume(state.volume)
        }
        modeSince = t
    }

    private func runMedia(_ action: MenuAction, t: TimeInterval) {
        effects.stopTimeReadout()
        effects.speak(.menuAction(action))
        effects.menu(action)
        enter(.clock, t: t)
    }

    /// 握る・首振りなどの取り消し
    func cancel(t: TimeInterval) {
        guard isActive else { return }
        effects.stopTimeReadout()
        effects.speak(.closed)
        enter(.idle, t: t)
    }

    /// 約 30Hz で呼ぶ
    func update(t: TimeInterval, reading r: WristReading) {
        reading = r
        if let p = pending, !state.dragging {
            let moved = hypot(wrapDegrees(r.roll - p.roll), r.elevation - p.elev) > config.moveThreshold
            if moved && p.count == 1 && (state.mode == .clock || state.mode == .volume) {
                pending = nil
                state.pendingPinches = 0
                beginDrag(t: t)
            } else if t - p.last > (countsPinches ? config.menuTapWindow : config.tapWindow) {
                pending = nil
                state.pendingPinches = 0
                tap(count: p.count, t: t)
            }
        }
        if state.dragging { drag(t: t) }
        if state.mode == .menu && pending == nil && t - modeSince > config.menuTimeout {
            effects.speak(.menuClosed)
            enter(.clock, t: t)
        }
    }

    // MARK: 内部

    private func enter(_ m: AirMode, t: TimeInterval) {
        state.mode = m
        state.dragging = false
        state.pendingPinches = 0
        pending = nil
        modeSince = t
    }

    /// ピンチの回数で操作を選ぶ状態か（回数を数えるので確定まで長めに待つ）
    private var countsPinches: Bool { state.mode == .menu }

    private func tap(count: Int, t: TimeInterval) {
        switch state.mode {
        case .menu:
            // ピンチ 1 回 = 再生・停止、2 回 = 次の曲、3 回以上 = 前の曲
            runMedia(count == 1 ? .playPause : count == 2 ? .nextTrack : .previousTrack, t: t)
        case .clock, .volume:
            effects.stopTimeReadout()
            enter(.menu, t: t)
            effects.speak(.menuOpened)
        case .idle, .ready:
            break
        }
    }

    private func beginDrag(t: TimeInterval) {
        if state.mode == .clock {
            effects.stopTimeReadout()
            enter(.volume, t: t)
            spokenVolumeStep = Int((state.volume * 10).rounded())
            effects.speak(.volume(Int((state.volume * 100).rounded())))
        }
        state.dragging = true
        anchor = (reading.roll, reading.elevation, state.volume)
        lastMove = t
    }

    private func drag(t: TimeInterval) {
        if reading.gyro > 0.35 { lastMove = t }
        let dRoll = wrapDegrees(reading.roll - anchor.roll) * (config.invertX ? -1 : 1)
        let dElev = reading.elevation - anchor.elev

        switch state.mode {
        case .volume:
            // 横（ひねり）でも縦（上下）でも動かせる
            state.volume = clamp(anchor.volume + dRoll / 60 + dElev / 45, 0, config.maxVolume)
            let step = Int((state.volume * 10).rounded())
            if step != spokenVolumeStep {
                spokenVolumeStep = step
                effects.tick()
                effects.speak(.percent(step * 10))
            }
            if t - lastVolumeSent > 0.2 {
                lastVolumeSent = t
                effects.setVolume(state.volume)
            }
        default:
            break
        }

        if t - lastMove > config.stillTime { endDrag(t: t) }
    }

    private func endDrag(t: TimeInterval) {
        state.dragging = false
        switch state.mode {
        case .volume:
            effects.setVolume(state.volume)
            effects.speak(.volume(Int((state.volume * 100).rounded())))
            enter(.clock, t: t)
        default:
            break
        }
    }
}
