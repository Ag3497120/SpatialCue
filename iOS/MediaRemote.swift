import Darwin
import Foundation

/// iOS の非公開フレームワーク MediaRemote で「再生中のアプリ」にコマンドを送る（実験）。
/// どのアプリが再生していても効く可能性があるが、公開 API ではないので iOS の版によっては無視される。
/// SC_PRIVATE_API（Config/App.xcconfig）を空にすると、この機能を含まずにビルドされる。
enum MediaRemote {
    enum Command: UInt32 {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

#if PRIVATE_MEDIAREMOTE
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let sendCommand: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    static var isAvailable: Bool { sendCommand != nil }

    @discardableResult
    static func send(_ c: Command) -> Bool { sendCommand?(c.rawValue, nil) ?? false }
#else
    // Config/App.xcconfig の SC_PRIVATE_API を空にしたビルド（TestFlight・App Store 向け）
    static var isAvailable: Bool { false }

    @discardableResult
    static func send(_ c: Command) -> Bool { false }
#endif
}
