import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .training: TrainingView()
                    case .sensors: SensorView()
                    }
                }
        }
        .overlay { GlanceGlow(active: model.reading.glancing || model.reading.palmGaze) }
        .overlay {
            if model.air.mode != .idle { VirtualOverlay() }
        }
        // アクセシビリティ →「クイックアクション」をオンにすると、システムが検出したダブルピンチがここに届く
        .accessibilityQuickAction(style: .outline) {
            Button(tr("ピンチ", "Pinch")) { model.pinch(from: .quickAction) }
        }
        .overlay(alignment: .topTrailing) {
            if let f = model.pinchFlash {
                PinchMark(flash: f)
                    .id(f.id)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: model.pinchFlash)
        .overlay(alignment: .top) {
            if let t = model.toast {
                Text(t)
                    .font(.headline)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }
}

/// ピンチを認識したときに右上に一瞬出るマーク
struct PinchMark: View {
    let flash: PinchFlash

    var body: some View {
        VStack(spacing: 1) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: flash.accepted ? "hand.pinch.fill" : "hand.pinch")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(flash.accepted ? Color.white : Color.gray)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(flash.accepted ? Color.cyan : Color.gray.opacity(0.3)))
                    .overlay {
                        if !flash.accepted {
                            Rectangle().fill(Color.gray).frame(width: 3, height: 40).rotationEffect(.degrees(45))
                        }
                    }
                if flash.count >= 2 {
                    Text("\(flash.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white))
                        .offset(x: 4, y: -4)
                }
            }
            Text(flash.source.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 4)
        .allowsHitTesting(false)
    }
}

/// Vision Pro の手の上に出るインジケーターの代わりに、画面の縁をほのかに光らせる
struct GlanceGlow: View {
    let active: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .strokeBorder(
                AngularGradient(colors: [.cyan, .purple, .blue, .cyan], center: .center),
                lineWidth: active ? 3 : 0)
            .opacity(active ? 0.8 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.3), value: active)
    }
}

struct StatusChip: View {
    let symbol: String
    let text: String
    let on: Bool

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background((on ? Color.green : Color.gray).opacity(0.25), in: Capsule())
            .foregroundStyle(on ? .primary : .secondary)
    }
}
