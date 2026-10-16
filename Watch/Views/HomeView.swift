import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var training: TrainingStore

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 0) {
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(ctx.date, format: .dateTime.month().day().weekday())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    StatusChip(symbol: "airpods", text: model.airPodsWorn ? tr("装着中", "Worn") : tr("振動のみ", "Haptics"), on: model.airPodsWorn)
                    StatusChip(symbol: "eye", text: headText, on: model.head != nil)
                }
                if !model.settings.gesturesEnabled {
                    StatusChip(symbol: "hand.raised.slash", text: tr("ジェスチャー停止中", "Gestures off"), on: false)
                }

                Text(hint)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(model.reading.glancing ? .primary : .secondary)
                    .animation(.default, value: model.reading.glancing)

                Button {
                    model.tellTime()
                } label: {
                    Label(tr("時刻を伝える", "Tell time"), systemImage: "waveform")
                }
                .handGestureShortcut(.primaryAction, isEnabled: model.air.mode == .idle)

                NavigationLink(value: Screen.training) {
                    Label(training.model == nil ? tr("学習（未学習）", "Training (none)") : tr("学習", "Training"),
                          systemImage: "hand.pinch.fill")
                }
                NavigationLink(value: Screen.sensors) {
                    Label(tr("センサー", "Sensors"), systemImage: "waveform.path.ecg")
                }
                Text(tr("設定は iPhone の SpatialCue で", "Settings are in SpatialCue on iPhone"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("SpatialCue")
    }

    private var headText: String {
        guard let h = model.head else { return tr("向きなし", "No head") }
        return tr("見る \(Int(min(h.look, 1) * 100))%", "Look \(Int(min(h.look, 1) * 100))%")
    }

    private var hint: String {
        if !model.motionAvailable { return tr("このデバイスではモーションが使えません", "Motion isn't available on this device") }
        if model.reading.palmUp { return tr("手のひらを見る → ポン\n表へ素早く返す → 時刻", "Look at palm → pop\nFlip back quickly → time") }
        if model.reading.glancing { return tr("手のひらを返して見る → 表に戻す → 時刻", "Turn palm up, look, flip back → time") }
        return tr("手首を上げて時計を見る", "Raise your wrist and look")
    }
}
