import SwiftUI

/// 仮想ウィンドウの見た目。手のひらを上に向けている間は画面が下を向くので、
/// 主役は音と振動。これは表に返したときや、横から見ている人のための表示。
struct VirtualOverlay: View {
    @EnvironmentObject private var model: AppModel
    @State private var crown = 0.5
    @FocusState private var crownFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            content
            // ダブルタップ（Series 9 以降）もピンチとして扱う。
            // 見えないボタンはダブルタップの対象にならないことがあるので、画面下に普通のボタンとして置く
            VStack {
                Spacer()
                Button {
                    model.pinch(from: .doubleTap)
                } label: {
                    Label(tr("ピンチ", "Pinch"), systemImage: "hand.pinch.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .handGestureShortcut(.primaryAction)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.air.mode)
        // 時計の状態では Digital Crown で音量
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation($crown, from: 0, through: 1, by: 0.05, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onAppear {
            crown = model.air.volume
            crownFocused = true
        }
        .onChange(of: crown) { _, v in
            if abs(v - model.air.volume) > 0.001 { model.crownVolume(v) }
        }
        .onChange(of: model.air.volume) { _, v in
            if abs(v - crown) > 0.001 { crown = v }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.air.mode {
        case .ready:
            VStack(spacing: 8) {
                Image(systemName: "hand.raised.fill").font(.system(size: 36))
                Text(tr("準備完了", "Ready")).font(.headline)
                Text(tr("表に返す → 時刻", "Flip back → time")).font(.caption2).foregroundStyle(.secondary)
            }
        case .clock, .volume, .menu:
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if model.air.mode == .volume {
                    HStack {
                        Image(systemName: "speaker.fill")
                        ProgressView(value: model.air.volume).tint(.cyan)
                        Text("\(Int(model.air.volume * 100))%").monospacedDigit().font(.caption)
                    }
                } else if model.air.mode == .menu {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array([MenuAction.playPause, .nextTrack, .previousTrack].enumerated()), id: \.offset) { i, a in
                            Text(tr("\(i + 1)回: \(a.title)", "\(i + 1)×: \(a.title)"))
                                .foregroundStyle(model.air.pendingPinches == i + 1 ? .cyan : .primary)
                        }
                    }
                    .font(.system(size: 13))
                } else if model.settings.directMedia {
                    HStack {
                        Image(systemName: "speaker.fill").font(.caption2)
                        ProgressView(value: model.air.volume).tint(.cyan)
                        Text("\(Int(model.air.volume * 100))%").monospacedDigit().font(.caption2)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Label(tr("ダブルタップ: \(MenuAction.playPause.title)", "Double Tap: \(MenuAction.playPause.title)"),
                              systemImage: "hand.pinch")
                        Label(tr("右に払う: \(MenuAction.nextTrack.title)", "Flick right: \(MenuAction.nextTrack.title)"),
                              systemImage: "forward.fill")
                        Label(tr("左に払う: \(MenuAction.previousTrack.title)", "Flick left: \(MenuAction.previousTrack.title)"),
                              systemImage: "backward.fill")
                        Label(tr("竜頭: 音量", "Crown: volume"), systemImage: "digitalcrown.arrow.clockwise")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                } else {
                    Text(tr("ピンチして動かす → 音量\nピンチ1回 → メニュー", "Pinch and move → volume\nPinch once → menu"))
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        case .idle:
            EmptyView()
        }
    }
}
