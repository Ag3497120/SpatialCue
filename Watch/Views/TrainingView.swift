import SwiftUI

/// つまむ／握る／なし を録音して、時計の上でその場で学習する
struct TrainingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var training: TrainingStore

    var body: some View {
        List {
            if let label = model.recordingLabel {
                Section {
                    VStack(spacing: 4) {
                        Text(tr("録音中: \(label.title)", "Recording: \(label.title)")).font(.headline)
                        Text("\(model.recordedThisRun)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(label.recordHint)
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button(tr("停止して学習", "Stop and learn")) { model.stopRecording() }
                            .tint(.red)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Section {
                ForEach(GestureLabel.allCases) { label in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(label.title)
                            Text(tr("\(training.count(label)) 件", "\(training.count(label)) samples"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            model.startRecording(label)
                        } label: {
                            Image(systemName: "record.circle").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.recordingLabel != nil)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            training.remove(label)
                        } label: {
                            Label(tr("削除", "Delete"), systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text(tr("ジェスチャー", "Gestures"))
            } footer: {
                Text(tr("各10件以上がおすすめ。「なし」も録ると誤反応が減ります。左にスワイプで削除。",
                        "Record 10+ samples each. Recording \"None\" too reduces false triggers. Swipe left to delete."))
            }

            Section(tr("モデル", "Model")) {
                Text(modelStatus).font(.system(size: 13))
                Text(tr("最後の認識: \(model.lastGesture)", "Last: \(model.lastGesture)")).font(.system(size: 13))
            }

            Section {
                Button {
                    model.exportTraining()
                } label: {
                    Label(tr("iPhoneへ書き出し", "Export to iPhone"), systemImage: "square.and.arrow.up")
                }
                .disabled(training.samples.isEmpty)
            } footer: {
                Text(tr("Create ML の Activity Classifier 用 CSV を iPhone アプリに送ります。",
                        "Sends a CSV for Create ML's Activity Classifier to the iPhone app."))
            }
        }
        .navigationTitle(tr("学習", "Training"))
    }

    private var modelStatus: String {
        guard let m = training.model else {
            return tr("未学習（簡易判定で「つまむ」を検出中）", "Not trained (using a simple pinch detector)")
        }
        if let acc = m.looAccuracy {
            return tr("学習済み・交差検証 \(Int(acc * 100))%", "Trained, cross-validation \(Int(acc * 100))%")
        }
        return tr("学習済み（データが少なめ）", "Trained (few samples)")
    }
}
