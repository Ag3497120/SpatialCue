import AVFoundation

/// 「ポン」という短い効果音をその場で合成して鳴らす（音声ファイル不要）
final class SoundFX {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var popBuffer: AVAudioPCMBuffer? = makePop()

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func playPop(volume: Float = 0.8) {
        guard let buffer = popBuffer else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// オーディオセッションを手放す前に止める（動いていると非アクティブにできない）
    func stop() {
        player.stop()
        engine.stop()
    }

    /// 660Hz から 1320Hz へ一瞬で上がって減衰する、泡が弾けるような音
    private func makePop() -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(sr * 0.12)
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let ch = b.floatChannelData?[0] else { return nil }
        b.frameLength = frames
        var phase = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let freq = 660 + 660 * min(t / 0.02, 1)
            phase += 2 * .pi * freq / sr
            let attack = min(t / 0.003, 1)
            ch[i] = Float(sin(phase) * attack * exp(-t * 40) * 0.9)
        }
        return b
    }
}
