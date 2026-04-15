import AppKit
import SwiftUI

enum IslandMode: Equatable {
    case recording(deviceName: String, locked: Bool)
    case transcribing
}

@MainActor
final class StatusIslandState: ObservableObject {
    @Published var mode: IslandMode = .transcribing
}

@MainActor
final class StatusIslandController {
    private var panel: NSPanel?
    let state = StatusIslandState()

    func show(mode: IslandMode) {
        state.mode = mode

        guard panel == nil else { return }

        let w: CGFloat = 280
        let h: CGFloat = 40

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: w, height: h)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = StatusIslandView(state: state)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: w, height: h))
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let f = screen.frame
            panel.setFrameOrigin(CGPoint(
                x: f.midX - w / 2,
                y: f.maxY - h - 6
            ))
        }

        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func updateMode(_ mode: IslandMode) {
        state.mode = mode
    }

    func dismiss() {
        guard let panel else { return }
        let ref = panel
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ref.animator().alphaValue = 0
        }, completionHandler: {
            ref.orderOut(nil)
        })
    }
}

// MARK: - Island View

struct StatusIslandView: View {
    @ObservedObject var state: StatusIslandState

    var body: some View {
        HStack {
            Spacer()
            pill
            Spacer()
        }
        .frame(height: 40)
    }

    @ViewBuilder
    private var pill: some View {
        HStack(spacing: 8) {
            switch state.mode {
            case .recording(let deviceName, let locked):
                PulsingDot()
                Text(deviceName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }

            case .transcribing:
                TranscribingDots()
                Text("Transcribing")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.black.opacity(0.78))
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Pulsing red dot

struct PulsingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 7, height: 7)
            .shadow(color: .red.opacity(pulse ? 0.7 : 0.3), radius: pulse ? 6 : 3)
            .scaleEffect(pulse ? 1.15 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Transcribing dots animation

struct TranscribingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(phase == i ? 0.9 : 0.3))
                    .frame(width: 4, height: 4)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}
