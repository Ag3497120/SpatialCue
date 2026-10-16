import Foundation

/// 配布の種類。
/// - フル版: ソースから自分でビルドする版。すべての機能が入る
/// - 安定版: TestFlight で配る版。審査で指摘されそうな機能（ワークアウトモード・延長実行・
///   無音再生での常駐・非公開 API）を外し、アプリを開いている間だけ動く
enum Edition {
#if STABLE_EDITION
    static let isStable = true
#else
    static let isStable = false
#endif

    static var title: String { isStable ? tr("安定版", "Stable") : tr("フル版", "Full") }
}
