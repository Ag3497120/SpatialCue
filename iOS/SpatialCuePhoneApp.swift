import MediaPlayer
import SwiftUI

@main
struct SpatialCuePhoneApp: App {
    @StateObject private var hub = PhoneHub()

    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environmentObject(hub)
                .task { hub.start() }
        }
    }
}

/// トップ画面: 状態とよく使う設定だけ。残りは分類ごとの画面へ
struct PhoneContentView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StatusRow(title: tr("Apple Watch", "Apple Watch"),
                              ok: hub.watchReachable,
                              detail: hub.watchReachable ? tr("接続中", "Connected") : tr("未接続", "Not connected"))
                    LabeledContent(tr("最後の操作", "Last action"), value: hub.lastCommand)
                } footer: {
                    Text(Edition.title)
                }

                Section {
                    Toggle(isOn: $hub.settings.gesturesEnabled) {
                        Label(tr("ジェスチャーを使う", "Use gestures"), systemImage: "hand.raised.fill")
                    }
                }

                Section(tr("よく使う設定", "Quick settings")) {
                    Picker(tr("時刻の伝え方", "Tell time with"), selection: $hub.settings.timeStyle) {
                        ForEach(TimeAnnounceStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle(tr("読み上げ", "Speech"), isOn: $hub.settings.speechEnabled)
                    Picker(tr("音の出力先", "Sound output"), selection: $hub.settings.soundOutput) {
                        ForEach(SoundOutput.allCases) { Text($0.title).tag($0) }
                    }
                    Button {
                        hub.sendCommand(.testTime)
                    } label: {
                        Label(tr("Watch で時刻を試す", "Try the time on Watch"), systemImage: "applewatch.radiowaves.left.and.right")
                    }
                }

                Section(tr("設定", "Settings")) {
                    NavigationLink { TimeSettingsView() } label: {
                        Label(tr("時刻と振動", "Time & haptics"), systemImage: "clock")
                    }
                    NavigationLink { SoundSettingsView() } label: {
                        Label(tr("音と言語", "Sound & language"), systemImage: "speaker.wave.2")
                    }
                    NavigationLink { MusicSettingsView() } label: {
                        Label(tr("音楽の操作", "Music controls"), systemImage: "music.note")
                    }
                    NavigationLink { GestureSettingsView() } label: {
                        Label(tr("ジェスチャー", "Gestures"), systemImage: "hand.wave")
                    }
                    NavigationLink { SafetySettingsView() } label: {
                        Label(tr("安全", "Safety"), systemImage: "checkmark.shield")
                    }
                    NavigationLink { HeadTrackingSettingsView() } label: {
                        Label(tr("AirPods（任意）", "AirPods (optional)"), systemImage: "airpodspro")
                    }
                    NavigationLink { RunningSettingsView() } label: {
                        Label(tr("動作と電池", "Running & battery"), systemImage: "battery.75percent")
                    }
                }

                Section {
                    NavigationLink { HowToView() } label: {
                        Label(tr("使い方", "How to use"), systemImage: "questionmark.circle")
                    }
                    NavigationLink { TrainingDataView() } label: {
                        Label(tr("学習データ", "Training data"), systemImage: "doc.text")
                    }
                    NavigationLink { StatusDetailView() } label: {
                        Label(tr("詳しい状態", "Details"), systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("SpatialCue")
            .background { SystemVolumeView(hub: hub).frame(width: 1, height: 1).opacity(0.01) }
        }
    }
}

// MARK: - 時刻と振動

private struct TimeSettingsView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        Form {
            Section {
                Picker(tr("時刻の伝え方", "Tell time with"), selection: $hub.settings.timeStyle) {
                    ForEach(TimeAnnounceStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker(tr("振動のパターン", "Vibration pattern"), selection: $hub.settings.hapticPattern) {
                    ForEach(HapticPattern.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text(hub.settings.hapticPattern.explanation)
            }
            Section {
                VStack(alignment: .leading) {
                    Text(tr("手のひらを返してから \(Self.seconds(hub.settings.timeDelay))",
                            "Start \(Self.secondsEN(hub.settings.timeDelay)) after flipping your palm"))
                    Slider(value: $hub.settings.timeDelay, in: 0...3, step: 0.25)
                }
            } header: {
                Text(tr("始めるまでの時間", "Delay"))
            } footer: {
                Text(tr("手のひらを返してから、振動と読み上げを始めるまでの時間です。待っている間に手を下ろすと取り消します。待つ時間が長いと、その間に Watch の画面が消えて伝わらないことがあります。",
                        "How long to wait after you flip your palm before the vibration and speech start. Lowering your hand while waiting cancels it. With a long delay, the Watch screen may turn off before the time is told."))
            }
            Section {
                Button(tr("Watch で試す", "Try on Watch")) { hub.sendCommand(.testTime) }
            } footer: {
                Text(tr("「試す」はすぐに鳴らします。「読み上げ」を選んでいても、読み上げがオフのときは振動で伝えます。",
                        "\"Try\" plays right away. Even with \"Voice\", the time is vibrated when speech is off."))
            }
        }
        .navigationTitle(tr("時刻と振動", "Time & haptics"))
    }

    static func seconds(_ v: Double) -> String {
        v <= 0 ? "すぐに始める" : String(format: "%g 秒後に始める", v)
    }

    static func secondsEN(_ v: Double) -> String {
        v <= 0 ? "right away" : String(format: "%g s", v)
    }
}

// MARK: - 音と言語

private struct SoundSettingsView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        Form {
            Section {
                Toggle(tr("読み上げ", "Speech"), isOn: $hub.settings.speechEnabled)
                if hub.settings.speechEnabled {
                    Picker(tr("読み上げの言語", "Speech language"), selection: $hub.settings.speechLanguage) {
                        ForEach(SpeechLanguageChoice.allCases) { Text($0.title).tag($0) }
                    }
                }
                Toggle(tr("「ポン」の音", "\"Pop\" sound"), isOn: $hub.settings.popSound)
                Picker(tr("音の出力先", "Sound output"), selection: $hub.settings.soundOutput) {
                    ForEach(SoundOutput.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text(tr("「ポン」は手のひらを見たときに鳴る音で、オフにしても軽い振動は残ります。出力先は、読み上げと「ポン」の効果音を鳴らす場所です。「iPhone」なら iPhone のスピーカーかつないでいるイヤホンで、「Apple Watch のスピーカー」なら Watch から鳴らします。Watch のスピーカーは、Watch の画面が点いている間だけ鳴ります。読み上げをオフにすると、振動と効果音だけで伝えます。",
                        "The pop plays when you look at your palm; with it off, a light tap remains. Sound output is where speech and the pop play. \"iPhone\" uses the iPhone speaker or connected headphones; \"Apple Watch speaker\" plays from the Watch, but only while the Watch screen is on. With speech off, only haptics and sound effects are used."))
            }
            Section(tr("言語", "Language")) {
                Picker(tr("アプリの言語", "App language"), selection: $hub.settings.appLanguage) {
                    ForEach(LanguageChoice.allCases) { Text($0.title).tag($0) }
                }
            }
        }
        .navigationTitle(tr("音と言語", "Sound & language"))
    }
}

// MARK: - 音楽の操作

private struct MusicSettingsView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        Form {
            Section {
                Toggle(tr("メニューを省略（時計で直接操作）", "Skip the menu (control from the clock)"),
                       isOn: $hub.settings.directMedia)
            } footer: {
                Text(tr("オンなら、時刻を聞いた後の時計の状態でそのまま操作します。オフなら、ピンチ1回でメニューを開いてから回数で選びます。",
                        "On: control music right from the clock after hearing the time. Off: pinch once to open a menu, then pinch to choose."))
            }
            Section(tr("割り当て", "Controls")) {
                if hub.settings.directMedia {
                    LabeledContent(tr("ダブルタップ", "Double Tap"), value: MenuAction.playPause.title)
                    LabeledContent(tr("右に払う", "Flick right"), value: MenuAction.nextTrack.title)
                    LabeledContent(tr("左に払う", "Flick left"), value: MenuAction.previousTrack.title)
                    LabeledContent("Digital Crown", value: tr("音量", "Volume"))
                } else {
                    LabeledContent(tr("ピンチ1回", "Pinch once"), value: MenuAction.playPause.title)
                    LabeledContent(tr("ピンチ2回", "Pinch twice"), value: MenuAction.nextTrack.title)
                    LabeledContent(tr("ピンチ3回", "Pinch 3 times"), value: MenuAction.previousTrack.title)
                }
            }
            Section {
                HStack {
                    Button(MenuAction.playPause.title) { hub.perform(.playPause) }
                    Spacer()
                    Button(tr("前", "Prev")) { hub.perform(.previousTrack) }
                    Button(tr("次", "Next")) { hub.perform(.nextTrack) }
                }
                .buttonStyle(.bordered)
                LabeledContent(tr("最後の操作", "Last action"), value: hub.lastCommand)
            } header: {
                Text(tr("ここで試す", "Try it here"))
            } footer: {
                Text(tr("ミュージックアプリの再生を操作します。", "Controls playback in the Music app."))
            }
            if hub.mediaRemoteAvailable {
                Section {
                    Toggle(tr("他のアプリも操作（実験）", "Control other apps (experimental)"),
                           isOn: $hub.settings.experimentalMediaRemote)
                } footer: {
                    Text(tr("Spotify など他のアプリを、iOS 内部の非公開機能（MediaRemote）で操作します。効かない場合は音声の割り込みで一時停止させます（再開は元のアプリの対応しだい）。",
                            "Controls other apps such as Spotify with iOS's private MediaRemote framework, falling back to pausing them with an audio interruption (whether they resume depends on the app)."))
                }
            }
        }
        .navigationTitle(tr("音楽の操作", "Music controls"))
    }
}

// MARK: - ジェスチャー

private struct GestureSettingsView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        Form {
            Section(tr("払う動き", "Flick")) {
                SliderRow(title: tr("感度", "Sensitivity"), value: $hub.settings.flickSensitivity, range: 0...1, step: 0.1, percent: true)
                Toggle(tr("向きを反転", "Invert direction"), isOn: $hub.settings.invertFlick)
            }
            Section(tr("装着", "Wearing")) {
                Picker(tr("装着の向き", "Watch orientation"), selection: $hub.settings.wristSetup) {
                    ForEach(WristSetup.allCases) { Text($0.title).tag($0) }
                }
                Toggle(tr("音量の左右反転", "Invert volume direction"), isOn: $hub.settings.invertVolumeX)
            }
            Section {
                Toggle(tr("手首の動きでピンチを推定（実験）", "Detect pinches from wrist motion (experimental)"),
                       isOn: $hub.settings.wristPinch)
                if hub.settings.wristPinch {
                    SliderRow(title: tr("つまむ感度", "Pinch sensitivity"), value: $hub.settings.pinchSensitivity,
                              range: 0...1, step: 0.1, percent: true)
                }
            } header: {
                Text(tr("ピンチ", "Pinch"))
            } footer: {
                Text(tr("確実なのは Watch のダブルタップ（Series 9／Ultra 2 以降）と、アクセシビリティのクイックアクションです。手首の動きからの推定は、手を開くなどの動きでも反応することがあります。使う場合は Watch の「学習」でピンチと「なし」を録ってください。",
                        "Double Tap (Series 9 / Ultra 2 or later) and Accessibility Quick Actions are the reliable options. Detection from wrist motion can also trigger on opening your hand; if you use it, record pinches and \"None\" in Training on the Watch."))
            }
        }
        .navigationTitle(tr("ジェスチャー", "Gestures"))
    }
}

// MARK: - 安全

private struct SafetySettingsView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        Form {
            Section {
                Toggle(tr("イヤホン接続時のみ再生・曲送り", "Media controls only with headphones"),
                       isOn: $hub.settings.mediaOnlyWithHeadphones)
                Toggle(tr("イヤホンが無いときは振動のみ", "Vibration only without headphones"),
                       isOn: $hub.settings.vibrationOnlyWithoutHeadphones)
            } header: {
                Text(tr("イヤホン", "Headphones"))
            } footer: {
                Text(tr("イヤホン（AirPods 以外も可）は外すと出力がスピーカーに戻るので、出力先がイヤホンのときを「装着中」とみなします。オフなら iPhone のスピーカーでも使えます。",
                        "Headphones (any brand) switch the output back to the speaker when taken off, so they count as worn while the output is headphones. With these off, it also works through the iPhone speaker."))
            }
            Section {
                Toggle(tr("腕を大きく動かしている間は無視", "Ignore while arm is moving"), isOn: $hub.settings.blockWhileMoving)
                SliderRow(title: tr("音量の上限", "Max volume"), value: $hub.settings.maxVolume, range: 0.3...1, step: 0.05, percent: true)
            } footer: {
                Text(tr("歩いたり走ったりして腕を振っている間の手首の衝撃は、ピンチとして扱いません。音量は上限を超えません。",
                        "Wrist impacts while swinging your arms aren't treated as pinches. The volume never goes above the limit."))
            }
        }
        .navigationTitle(tr("安全", "Safety"))
    }
}

// MARK: - AirPods（任意）

private struct HeadTrackingSettingsView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        Form {
            Section {
                Toggle(tr("頭の向きを判定に使う", "Use head tracking"), isOn: $hub.settings.useHeadTracking)
            } footer: {
                Text(tr("オフでも手首の動きだけで使えます。オンにすると、AirPods Pro／Max／第3世代以降の頭の向きで「手のひらを見ているか」を確かめ、うなずき（決定）・首振り（閉じる）も使えます。",
                        "SpatialCue works with wrist motion alone. Turn this on to use AirPods Pro / Max / 3rd gen or later head tracking to check that you're looking at your palm, and to use nods (select) and head shakes (close)."))
            }
            if hub.settings.useHeadTracking {
                Section(tr("頭の向き", "Head")) {
                    LiveHeadRows(live: hub.live)
                    LabeledContent(tr("最後の頭ジェスチャー", "Last head gesture"), value: hub.lastEvent)
                    Toggle(tr("見ている時だけ反応", "Only while looking"), isOn: $hub.settings.requireHeadLook)
                    SliderRow(title: tr("見ている判定のしきい値", "Looking threshold"), value: $hub.settings.headLookThreshold,
                              range: 0.2...1, step: 0.1, percent: true)
                }
                Section {
                    Button(tr("① 正面を見てタップ", "① Look straight ahead and tap")) { hub.captureNeutral() }
                    Button(tr("② 腕を上げて時計を見る姿勢でタップ", "② Raise your wrist, look at the Watch, and tap")) { hub.captureLook() }
                    LabeledContent(tr("状態", "Status"), value: hub.calibration.calibrated
                                   ? String(format: tr("正面 %.0f° / 時計 %.0f°", "Ahead %.0f° / Watch %.0f°"),
                                            hub.calibration.neutralPitch, hub.calibration.lookPitch)
                                   : tr("未校正（下向き30°を仮定）", "Not calibrated (assumes 30° down)"))
                } header: {
                    Text(tr("頭の校正", "Head calibration"))
                }
                Section {
                    Button(tr("手のひらを見て校正（Watch で3秒後に記録）", "Calibrate palm (Watch records after 3 s)")) {
                        hub.sendCommand(.calibratePalm)
                    }
                    LabeledContent(tr("状態", "Status"),
                                   value: hub.watchPalmCalibrated ? tr("校正済み", "Calibrated") : tr("未校正", "Not calibrated"))
                    if hub.watchPalmCalibrated {
                        Button(tr("左右の向きを反転", "Flip left/right")) { hub.sendCommand(.flipPalmYaw) }
                        Button(tr("校正を消す", "Clear calibration"), role: .destructive) { hub.sendCommand(.clearPalm) }
                    }
                    SliderRow(title: tr("視線の許容角", "Gaze tolerance"), value: $hub.settings.gazeThreshold,
                              range: 10...45, step: 5, suffix: "°")
                } header: {
                    Text(tr("手のひらの校正", "Palm calibration"))
                } footer: {
                    Text(tr("ボタンを押したら手のひらを上に向けて見てください。Watch がカウントダウン後に記録します。",
                            "After tapping, turn your palm up and look at it. The Watch records after a countdown."))
                }
            }
        }
        .navigationTitle(tr("AirPods（任意）", "AirPods (optional)"))
    }
}

// MARK: - 動作と電池

private struct RunningSettingsView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        Form {
            if !Edition.isStable {
                Section {
                    Toggle(tr("常駐（ワークアウトモード）", "Stay running (workout mode)"), isOn: $hub.settings.workoutMode)
                    if !hub.settings.workoutMode {
                        Toggle(tr("常時検出（最長1時間）", "Keep detecting (up to 1 hour)"), isOn: $hub.settings.keepRunning)
                    }
                    Toggle(tr("画面ロック中も中継（無音再生）", "Relay while locked (silent audio)"), isOn: $hub.keepAliveInBackground)
                } footer: {
                    Text(tr("ワークアウトモードは止めるまで Watch で動き続けます（ヘルスケアには記録しません。心拍センサーはシステムがオンにします）。電池を多く使います。",
                            "Workout mode keeps the Watch app running until you turn it off (nothing is saved to Health; the system turns on the heart-rate sensor). It uses more battery."))
                }
            }
            Section {
                Toggle(tr("省電力モード", "Low Power Mode"), isOn: $hub.settings.lowPower)
            } footer: {
                Text(tr("センサーの読み取りを 1 秒 100 回から 50 回に、画面の更新を 1 秒 5 回に減らします。手のひら・表に返す・払う動きの判定には十分です。手首の衝撃でのピンチ推定を使うときと学習の録音中は、自動で 100 回に戻します。",
                        "Reads the motion sensors 50 times a second instead of 100, and refreshes the screen 5 times a second. That's enough for the palm, flip, and flick gestures. It switches back to 100 automatically for wrist-pinch detection and while recording training data."))
            }
            Section {
                Toggle(tr("腕を下ろしたら省電力", "Save power when arm is down"), isOn: $hub.settings.powerSaving)
            } footer: {
                Text(Edition.isStable
                     ? tr("Watch で SpatialCue を開いている間だけ動きます。Watch の「設定」→「一般」→「時計に戻る」→ SpatialCue を「App に戻る」にすると、手首を下ろしても開いたままになります。",
                          "Works while SpatialCue is open on the Watch. On the Watch, set Settings → General → Return to Clock → SpatialCue to \"Return to App\" to keep it open when you lower your wrist.")
                     : tr("腕を3秒下ろすと、センサーの読み取りを減らして電池を節約します。",
                          "With your arm down for 3 seconds, sensor sampling drops to save battery."))
            }
        }
        .navigationTitle(tr("動作と電池", "Running & battery"))
    }
}

// MARK: - 使い方・学習データ・詳しい状態

private struct HowToView: View {
    var body: some View {
        Form {
            Section {
                Text(tr("① 手のひらを上に向けて見る → ポン（準備完了）", "① Turn your palm up and look at it → pop (ready)"))
                Text(tr("② 表へ素早く返す → 時刻", "② Flip back quickly → time"))
                Text(tr("③ 時計が出ている間: ダブルタップ → 再生・停止、右／左に払う → 曲送り／曲戻し、竜頭 → 音量",
                        "③ While the clock is shown: Double Tap → play/pause, flick right/left → next/previous, crown → volume"))
                Text(tr("握る／首振り → 閉じる", "Fist / head shake → close"))
            }
        }
        .navigationTitle(tr("使い方", "How to use"))
    }
}

private struct TrainingDataView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        Form {
            Section {
                if hub.exports.isEmpty {
                    Text(tr("Watch の「学習」→「iPhoneへ書き出し」で届きます", "Use Training → Export to iPhone on the Watch"))
                        .foregroundStyle(.secondary)
                }
                ForEach(hub.exports, id: \.self) { url in
                    ShareLink(item: url) {
                        Label(url.lastPathComponent, systemImage: "doc.text")
                    }
                }
                .onDelete { hub.deleteExports(at: $0) }
            } footer: {
                Text(tr("Create ML の Activity Classifier 用の CSV です。", "CSV files for Create ML's Activity Classifier."))
            }
        }
        .navigationTitle(tr("学習データ", "Training data"))
    }
}

private struct StatusDetailView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("版", "Edition"), value: Edition.title)
                StatusRow(title: tr("Apple Watch アプリ", "Apple Watch app"), ok: hub.watchAppInstalled)
                StatusRow(title: tr("Watch と通信中", "Connected to Watch"), ok: hub.watchReachable)
                LabeledContent(tr("Watch の常駐", "Watch background"), value: hub.watchResidency)
            }
            Section {
                StatusRow(title: tr("イヤホン", "Headphones"), ok: hub.headphonesOn)
                LabeledContent(tr("音声の出力先", "Audio output"), value: hub.outputName)
                StatusRow(title: tr("AirPods（頭の向き）", "AirPods (head motion)"), ok: hub.airPodsConnected)
                LabeledContent(tr("モーションの許可", "Motion permission"), value: hub.authorization)
            }
            Section {
                LabeledContent(tr("最後の操作", "Last action"), value: hub.lastCommand)
            }
        }
        .navigationTitle(tr("詳しい状態", "Details"))
    }
}

// MARK: - 部品

private struct StatusRow: View {
    let title: String
    let ok: Bool
    var detail: String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                if let detail { Text(detail).foregroundStyle(.secondary) }
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(ok ? .green : .secondary)
            }
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var percent = false
    var suffix = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(percent ? "\(title) \(Int((value * 100).rounded()))%" : "\(title) \(Int(value))\(suffix)")
            Slider(value: $value, in: range, step: step)
        }
    }
}

/// 頭の向きの表示。ここだけが頻繁に描き直される
private struct LiveHeadRows: View {
    @ObservedObject var live: HeadLive

    var body: some View {
        LabeledContent(tr("ピッチ", "Pitch"), value: String(format: "%.0f°", live.pitch))
        LabeledContent(tr("ヨー", "Yaw"), value: String(format: "%.0f°", live.yaw))
        Gauge(value: min(live.look, 1)) {
            Text(tr("時計を見ている度合い", "Looking at Watch"))
        } currentValueLabel: {
            Text("\(Int(live.look * 100))%")
        }
    }
}

/// システム音量を動かすための非表示の MPVolumeView
struct SystemVolumeView: UIViewRepresentable {
    let hub: PhoneHub

    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        DispatchQueue.main.async {
            hub.volumeSlider = v.subviews.compactMap { $0 as? UISlider }.first
        }
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
