import HealthKit

/// ワークアウトセッションを使って、アプリをバックグラウンドで動かし続ける（止めるまで無制限）。
///
/// - 屋内・「その他」の種類で開始し、位置情報は使わない（GPS は動かない）
/// - HKLiveWorkoutBuilder を使わないので、ヘルスケアには何も記録されない
/// - 心拍センサーはワークアウト中にシステムが自動でオンにする（アプリからは止められない）
@MainActor
final class WorkoutKeeper: NSObject, ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var lastError: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func start() {
        guard isAvailable else { lastError = tr("この端末ではヘルスケアが使えません", "Health data isn't available on this device"); return }
        guard session == nil else { return }
        store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) { ok, error in
            Task { @MainActor in
                guard ok else {
                    self.lastError = error?.localizedDescription ?? tr("ワークアウトの許可がありません", "Workout permission was not granted")
                    return
                }
                self.begin()
            }
        }
    }

    func stop() {
        session?.end()
        session = nil
        active = false
    }

    private func begin() {
        guard session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            s.delegate = self
            s.startActivity(with: Date())
            session = s
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

extension WorkoutKeeper: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            self.active = toState == .running
            if toState == .ended || toState == .stopped { self.session = nil }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.lastError = message
            self.active = false
            self.session = nil
        }
    }
}
