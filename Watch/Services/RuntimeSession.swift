import WatchKit

/// 手首を下ろして画面が暗くなってもセンサーを読み続けるための延長実行セッション（最長 1 時間）。
@MainActor
final class RuntimeSession: NSObject, ObservableObject {
    @Published private(set) var active = false
    private var session: WKExtendedRuntimeSession?

    func start() {
        if let s = session, s.state == .running || s.state == .scheduled { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
    }

    func stop() {
        session?.invalidate()
        session = nil
        active = false
    }
}

extension RuntimeSession: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in self.active = true }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        Task { @MainActor in
            self.active = false
            self.session = nil
        }
    }
}
