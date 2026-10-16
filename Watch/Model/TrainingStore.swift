import Foundation

struct TrainingSample: Codable, Identifiable {
    var id = UUID()
    var label: GestureLabel
    var date = Date()
    var window: [Float]
}

/// 録音したジェスチャーの保存と、端末上でのモデル再構築
@MainActor
final class TrainingStore: ObservableObject {
    @Published private(set) var samples: [TrainingSample] = []
    @Published private(set) var model: KNNModel?

    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("gestures.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode([TrainingSample].self, from: data) {
            samples = s
        }
        rebuild()
    }

    func count(_ label: GestureLabel) -> Int { samples.filter { $0.label == label }.count }

    func add(_ label: GestureLabel, window: [Float]) {
        samples.append(TrainingSample(label: label, window: window))
    }

    func remove(_ label: GestureLabel) {
        samples.removeAll { $0.label == label }
        commit()
    }

    /// 保存してモデルを作り直す
    func commit() {
        if let data = try? JSONEncoder().encode(samples) { try? data.write(to: url, options: .atomic) }
        rebuild()
    }

    private func rebuild() {
        // 「つまむ」か「握る」が 3 件以上あるときだけ学習モデルを使う（それ以外は未学習ヒューリスティック）
        guard count(.pinch) >= 3 || count(.fist) >= 3 else { model = nil; return }
        model = KNNModel(samples: samples.map { (label: $0.label.rawValue, features: GestureFeatures.extract($0.window)) })
    }

    /// Create ML の Activity Classifier にそのまま読ませられる CSV を作る
    func exportCSV() throws -> URL {
        var csv = "session_id,label,t,ax,ay,az,gx,gy,gz\n"
        let ch = PinchDetector.channels
        for s in samples {
            for k in 0..<(s.window.count / ch) {
                let v = (0..<ch).map { String(format: "%.5f", s.window[k * ch + $0]) }.joined(separator: ",")
                csv += "\(s.id.uuidString),\(s.label.rawValue),\(String(format: "%.2f", Double(k) * 0.01)),\(v)\n"
            }
        }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("gestures-\(f.string(from: Date())).csv")
        try csv.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}
