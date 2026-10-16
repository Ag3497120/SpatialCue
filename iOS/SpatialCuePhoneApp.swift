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

struct PhoneContentView: View {
    @EnvironmentObject private var hub: PhoneHub

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $hub.settings.gesturesEnabled) {
                        Label(tr("ジェスチャーを使う", "Use gestures"), systemImage: "hand.raised.fill")
                    }
                } footer: {
                    Text(tr("オフにすると、Watch のすべての空中操作（ピンチ・手のひら・払う）を止めます。",
                            "Turn off to stop all air gestures on the Watch (pinch, palm, flick)."))
                }

                Section {
                    Picker(tr("アプリの言語", "App language"), selection: $hub.settings.appLanguage) {
                        ForEach(LanguageChoice.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle(tr("読み上げ", "Speech"), isOn: $hub.settings.speechEnabled)
                    if hub.settings.speechEnabled {
                        Picker(tr("読み上げの言語", "Speech language"), selection: $hub.settings.speechLanguage) {
                            ForEach(SpeechLanguageChoice.allCases) { Text($0.title).tag($0) }
                        }
                    }
                } header: {
                    Text(tr("言語と読み上げ", "Language & speech"))
                } footer: {
                    Text(tr("読み上げをオフにすると、時刻やメニューは振動と効果音だけで伝えます。",
                            "With speech off, time and menus are conveyed only by vibration and sound effects."))
                }

                Section(tr("状態", "Status")) {
                    status(tr("AirPods 装着", "AirPods worn"), hub.airPodsWorn)
                    LabeledContent(tr("音声の出力先", "Audio output"), value: hub.outputName)
                    status(tr("AirPods（頭の向き）", "AirPods (head motion)"), hub.airPodsConnected)
                    status(tr("Apple Watch アプリ", "Apple Watch app"), hub.watchAppInstalled)
                    status(tr("Watch と通信中", "Connected to Watch"), hub.watchReachable)
                    LabeledContent(tr("Watch の常駐", "Watch background"), value: hub.watchResidency)
                    LabeledContent(tr("最後の操作", "Last action"), value: hub.lastCommand)
                    LabeledContent(tr("モーションの許可", "Motion permission"), value: hub.authorization)
                }

                Section {
                    Toggle(tr("AirPods 装着時のみ再生・曲送り", "Media controls only with AirPods in"),
                           isOn: $hub.settings.mediaOnlyWithAirPods)
                    Toggle(tr("AirPods が無いときは振動のみ", "Vibration only without AirPods"),
                           isOn: $hub.settings.vibrationOnlyWithoutAirPods)
                    Toggle(tr("腕を大きく動かしている間は無視", "Ignore while arm is moving"),
                           isOn: $hub.settings.blockWhileMoving)
                    slider(tr("音量の上限", "Max volume"), value: $hub.settings.maxVolume, in: 0.3...1, step: 0.05, percent: true)
                } header: {
                    Text(tr("安全装置", "Safety"))
                } footer: {
                    Text(tr("AirPods は耳から外すと出力がスピーカーに戻るので、出力先が AirPods のときを「装着中」とみなします。装着していないと、再生・曲送りはせず、読み上げや効果音の代わりに Watch の振動だけで知らせます。歩いたり走ったりして腕を振っている間の手首の衝撃は、ピンチとして扱いません。音量スライダーは上限を超えません。",
                            "AirPods switch the output back to the speaker when taken out, so SpatialCue treats them as worn while the output is AirPods. When they aren't worn, media controls are ignored and the Watch uses vibration instead of speech and sounds. Wrist impacts while swinging your arms (walking, running) aren't treated as pinches. The volume slider never goes above the limit."))
                }

                Section {
                    Toggle(tr("メニューを省略（時計で直接操作）", "Skip the menu (control from the clock)"),
                           isOn: $hub.settings.directMedia)
                    if hub.settings.directMedia {
                        LabeledContent(tr("ダブルタップ", "Double Tap"), value: MenuAction.playPause.title)
                        LabeledContent(tr("右に払う", "Flick right"), value: MenuAction.nextTrack.title)
                        LabeledContent(tr("左に払う", "Flick left"), value: MenuAction.previousTrack.title)
                        LabeledContent(tr("Digital Crown", "Digital Crown"), value: tr("音量", "Volume"))
                    } else {
                        LabeledContent(tr("ピンチ1回", "Pinch once"), value: MenuAction.playPause.title)
                        LabeledContent(tr("ピンチ2回", "Pinch twice"), value: MenuAction.nextTrack.title)
                        LabeledContent(tr("ピンチ3回", "Pinch 3 times"), value: MenuAction.previousTrack.title)
                    }
                    Toggle(tr("他のアプリも操作（実験）", "Control other apps (experimental)"),
                           isOn: $hub.settings.experimentalMediaRemote)
                    if !hub.mediaRemoteAvailable {
                        Text(tr("このビルドでは使えません", "Not available in this build"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(MenuAction.playPause.title) { hub.perform(.playPause) }
                        Spacer()
                        Button(tr("前", "Prev")) { hub.perform(.previousTrack) }
                        Button(tr("次", "Next")) { hub.perform(.nextTrack) }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text(hub.settings.directMedia ? tr("音楽の操作（時計でピンチ）", "Music (pinch on the clock)")
                                                  : tr("メニュー（時計でピンチ1回）", "Menu (pinch once on the clock)"))
                } footer: {
                    Text(tr("「メニューを省略」がオンなら、時刻を聞いた後の時計の状態で、ダブルタップで再生・停止、手首を右／左に払って曲送り／曲戻し、Digital Crown で音量を変えます（払う向きが逆なら「ジェスチャー」→「払う向きを反転」）。オフなら、ピンチ1回でメニューを開いてから回数で選びます。ミュージックアプリは公式の方法で操作します。Spotify など他のアプリは「他のアプリも操作」をオンにすると iOS 内部の非公開機能（MediaRemote）で操作を試み、効かない場合は音声の割り込みで一時停止させます（再開は元のアプリの対応しだい）。ボタンでここから試せます。",
                            "With \"Skip the menu\" on, after hearing the time: Double Tap plays/pauses, flicking your wrist right/left skips forward/back, and the Digital Crown sets the volume (if the flick direction feels reversed, use Gestures → Invert flick direction). With it off, pinch once to open the menu, then pinch to choose. The Music app is controlled with the public API. For other apps such as Spotify, \"Control other apps\" tries iOS's private MediaRemote framework, and falls back to pausing them with an audio interruption (whether they resume depends on the app). Use the buttons to try it here."))
                }

                Section {
                    Picker(tr("時刻の伝え方", "Tell time with"), selection: $hub.settings.timeStyle) {
                        ForEach(TimeAnnounceStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(tr("振動のパターン", "Vibration pattern"), selection: $hub.settings.hapticPattern) {
                        ForEach(HapticPattern.allCases) { Text($0.title).tag($0) }
                    }
                    Button(tr("Watch で試す", "Try on Watch")) { hub.sendCommand(.testTime) }
                } header: {
                    Text(tr("時刻", "Time"))
                } footer: {
                    Text(hub.settings.hapticPattern.explanation + "\n"
                         + tr("「読み上げ」でも、読み上げがオフのときや AirPods が無いときは振動で伝えます。",
                              "Even with \"Voice\", the time is vibrated when speech is off or AirPods aren't worn."))
                }

                Section(tr("頭の向き（AirPods）", "Head (AirPods)")) {
                    LiveHeadRows(live: hub.live)
                    LabeledContent(tr("最後の頭ジェスチャー", "Last head gesture"), value: hub.lastEvent)
                    Toggle(tr("見ている時だけ反応", "Only while looking"), isOn: $hub.settings.requireHeadLook)
                    slider(tr("見ている判定のしきい値", "Looking threshold"), value: $hub.settings.headLookThreshold,
                           in: 0.2...1, step: 0.1, percent: true)
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
                } footer: {
                    Text(tr("AirPods を着けて、それぞれの姿勢のまま画面をタップします。",
                            "Wear your AirPods and tap while holding each posture."))
                }

                Section {
                    Button(tr("手のひらを見て校正（Watch で3秒後に記録）", "Calibrate palm (Watch records after 3 s)")) {
                        hub.sendCommand(.calibratePalm)
                    }
                    LabeledContent(tr("状態", "Status"), value: hub.watchPalmCalibrated ? tr("校正済み", "Calibrated") : tr("未校正", "Not calibrated"))
                    if hub.watchPalmCalibrated {
                        Button(tr("左右の向きを反転", "Flip left/right")) { hub.sendCommand(.flipPalmYaw) }
                        Button(tr("校正を消す", "Clear calibration"), role: .destructive) { hub.sendCommand(.clearPalm) }
                    }
                    slider(tr("視線の許容角", "Gaze tolerance"), value: $hub.settings.gazeThreshold, in: 10...45, step: 5, suffix: "°")
                } header: {
                    Text(tr("手のひらを見る", "Looking at palm"))
                } footer: {
                    Text(tr("ボタンを押したら手のひらを上に向けて見てください。Watch がカウントダウン後に、AirPods の向きと腕の向きを基準として記録します。",
                            "After tapping, turn your palm up and look at it. After a countdown the Watch records your head and arm direction as the reference."))
                }

                Section {
                    Toggle(tr("手首の動きでピンチを推定（実験）", "Detect pinches from wrist motion (experimental)"),
                           isOn: $hub.settings.wristPinch)
                    if hub.settings.wristPinch {
                        slider(tr("つまむ感度", "Pinch sensitivity"), value: $hub.settings.pinchSensitivity, in: 0...1, step: 0.1, percent: true)
                    }
                } header: {
                    Text(tr("ピンチの入力", "Pinch input"))
                } footer: {
                    Text(tr("確実なのは Watch のダブルタップ（Series 9／Ultra 2 以降）と、アクセシビリティのクイックアクション（ダブルピンチ）です。手首の動きからの推定は、手を開くなどの動きでも反応することがあります。使う場合は Watch の「学習」で、ピンチと「なし」（手を開く・指を動かす）を録ってください。",
                            "Double Tap on the Watch (Series 9 / Ultra 2 or later) and Accessibility Quick Actions (double pinch) are the reliable options. Detection from wrist motion can also trigger on things like opening your hand. If you use it, record pinches and \"None\" (opening your hand, moving your fingers) in Training on the Watch."))
                }

                Section(tr("ジェスチャー", "Gestures")) {
                    slider(tr("払う感度", "Flick sensitivity"), value: $hub.settings.flickSensitivity, in: 0...1, step: 0.1, percent: true)
                    Toggle(tr("音量の左右反転", "Invert volume direction"), isOn: $hub.settings.invertVolumeX)
                    Toggle(tr("払う向きを反転", "Invert flick direction"), isOn: $hub.settings.invertFlick)
                    Picker(tr("装着の向き", "Watch orientation"), selection: $hub.settings.wristSetup) {
                        ForEach(WristSetup.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Toggle(tr("常駐（ワークアウトモード）", "Stay running (workout mode)"), isOn: $hub.settings.workoutMode)
                    if !hub.settings.workoutMode {
                        Toggle(tr("常時検出（最長1時間）", "Keep detecting (up to 1 hour)"), isOn: $hub.settings.keepRunning)
                    }
                    Toggle(tr("腕を下ろしたら省電力", "Save power when arm is down"), isOn: $hub.settings.powerSaving)
                    Toggle(tr("画面ロック中も中継（無音再生）", "Relay while locked (silent audio)"), isOn: $hub.keepAliveInBackground)
                } header: {
                    Text(tr("常駐", "Background"))
                } footer: {
                    Text(tr("ワークアウトモードは止めるまで Watch で動き続けます（ヘルスケアには記録しません。心拍センサーはシステムがオンにします）。初回は Watch でヘルスケアの許可が出ます。「画面ロック中も中継」は iPhone をポケットに入れたまま使うときにオン。",
                            "Workout mode keeps the Watch app running until you turn it off (nothing is saved to Health; the system turns on the heart-rate sensor). The Watch asks for Health permission the first time. Turn on \"Relay while locked\" to use it with the iPhone in your pocket."))
                }

                Section(tr("学習データ（Create ML 用 CSV）", "Training data (CSV for Create ML)")) {
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
                }

                Section(tr("使い方", "How to use")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("・手のひらを上に向けて見る → ポン（準備完了）", "• Turn your palm up and look at it → pop (ready)"))
                        Text(tr("・表へ素早く返す → 時刻", "• Flip back quickly → time"))
                        Text(tr("・時計でピンチして動かす → 音量", "• On the clock, pinch and move → volume"))
                        Text(tr("・時計でダブルタップ → 再生・停止、右／左に払う → 曲送り／曲戻し、竜頭 → 音量",
                                "• On the clock: Double Tap → play/pause, flick right/left → next/previous, crown → volume"))
                        Text(tr("・握る／首振り → 閉じる", "• Fist / head shake → close"))
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle("SpatialCue")
            .background { SystemVolumeView(hub: hub).frame(width: 1, height: 1).opacity(0.01) }
        }
    }

    private func status(_ title: String, _ ok: Bool) -> some View {
        LabeledContent(title) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                        percent: Bool = false, suffix: String = "") -> some View {
        VStack(alignment: .leading) {
            Text(percent ? "\(title) \(Int((value.wrappedValue * 100).rounded()))%" : "\(title) \(Int(value.wrappedValue))\(suffix)")
            Slider(value: value, in: range, step: step)
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
