import SwiftUI

struct SensorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section(tr("手首", "Wrist")) {
                row(tr("ひねり", "Roll"), String(format: "%.0f°", model.reading.roll))
                row(tr("上下", "Elevation"), String(format: "%.0f°", model.reading.elevation))
                row(tr("姿勢", "Pose"), model.reading.pose.title)
                row(tr("見ている", "Glancing"), yesNo(model.reading.glancing))
                row(tr("手のひら上", "Palm up"), yesNo(model.reading.palmUp))
                row(tr("手のひらを見ている", "Looking at palm"), yesNo(model.reading.palmGaze))
                row(tr("手のひら方向", "Palm direction"),
                    String(format: "%.0f° / %.0f°", model.reading.palmAzimuth, model.reading.palmElevation))
                row(tr("視線のずれ", "Gaze error"), model.reading.gazeError.map { String(format: "%.0f°", $0) } ?? "—")
                row(tr("衝撃", "Jerk"), String(format: "%.1f G/s", model.reading.jerk))
            }
            Section(tr("頭（AirPods）", "Head (AirPods)")) {
                if let h = model.head {
                    row(tr("取得元", "Source"), h.source.title)
                    row(tr("ピッチ", "Pitch"), String(format: "%.0f°", h.pitch))
                    row(tr("ヨー", "Yaw"), String(format: "%.0f°", h.yaw))
                    row(tr("見る度合い", "Looking"), "\(Int(h.look * 100))%")
                } else {
                    Text(tr("データなし", "No data")).foregroundStyle(.secondary)
                }
            }
            Section(tr("安全装置", "Safety")) {
                row(tr("版", "Edition"), Edition.title)
                row(tr("イヤホン", "Headphones"), yesNo(model.headphonesOn))
                row(tr("音を出す", "Sound"), model.canUseSound ? tr("はい", "Yes") : tr("振動のみ", "Vibration only"))
                row(tr("ジェスチャー", "Gestures"), model.settings.gesturesEnabled ? tr("有効", "On") : tr("停止中", "Off"))
            }
            Section(tr("認識", "Recognition")) {
                row(tr("最後", "Last"), model.lastGesture)
                row(tr("仮想UI", "Virtual UI"), model.air.mode == .idle ? tr("待機", "Idle") : model.air.mode.title)
                row("iPhone", model.phone.reachable ? tr("接続中", "Connected") : tr("未接続", "Not connected"))
                row(tr("常駐", "Background"), model.workout.active ? tr("ワークアウト", "Workout")
                    : model.runtime.active ? tr("延長実行", "Extended runtime") : tr("なし", "None"))
            }
        }
        .font(.system(size: 13))
        .navigationTitle(tr("センサー", "Sensors"))
    }

    private func yesNo(_ b: Bool) -> String { b ? tr("はい", "Yes") : tr("いいえ", "No") }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).monospacedDigit()
        }
    }
}
