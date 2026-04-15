import AppKit
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var level: CGFloat = 0
    @Published var colorPhase: Double = 0
    @Published var flowPhase: Double = 0
    private var timer: Timer?
    private var rawLevel: CGFloat = 0

    private let warmHues: [Double] = [0.0, 0.02, 0.05, 0.08, 0.11, 0.13, 0.11, 0.08, 0.05, 0.02]

    var currentHue: Double {
        let idx = colorPhase * Double(warmHues.count - 1)
        let lo = Int(idx) % warmHues.count
        let hi = (lo + 1) % warmHues.count
        let frac = idx - Double(Int(idx))
        return warmHues[lo] + (warmHues[hi] - warmHues[lo]) * frac
    }

    func start() {
        colorPhase = 0
        flowPhase = 0
        rawLevel = 0
        level = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.colorPhase += 0.0008
                if self.colorPhase >= 1.0 { self.colorPhase -= 1.0 }
                self.flowPhase += 0.008
                if self.flowPhase >= 1.0 { self.flowPhase -= 1.0 }
                self.level += (self.rawLevel - self.level) * 0.2
            }
        }
    }

    func setRaw(_ raw: Float) {
        rawLevel = CGFloat(raw)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class RecordingOverlayController {
    private var panel: NSPanel?
    let state = OverlayState()

    func show() {
        guard panel == nil else { return }

        let screenW = NSScreen.main?.frame.width ?? 3000
        let w = screenW
        let h: CGFloat = 1000

        let size = CGSize(width: w, height: h)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = RecordingAuraView(state: state, viewWidth: w, viewHeight: h)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let f = screen.frame
            panel.setFrameOrigin(CGPoint(
                x: f.midX - w / 2,
                y: f.maxY - h
            ))
        }

        state.start()
        panel.orderFront(nil)
        self.panel = panel
    }

    func dismiss() {
        state.stop()
        panel?.orderOut(nil)
        panel = nil
    }
}

struct RecordingAuraView: View {
    @ObservedObject var state: OverlayState
    let viewWidth: CGFloat
    let viewHeight: CGFloat

    // Horizontal stretch factor — makes circle into wide oval
    private let stretchX: CGFloat = 4.0

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let level = state.level
            let hue = state.currentHue
            let flow = state.flowPhase

            // 3 glow layers, drawn with horizontal stretch for true oval gradient
            for i in 0..<3 {
                let fi = CGFloat(i)
                let layerHue = hue + Double(i) * 0.03

                // 75% base + 25% from voice
                let spread: CGFloat = 0.75 + level * 0.25

                // Fluid wobble per layer
                let wobble = CGFloat(sin((flow + Double(i) * 0.33) * .pi * 2)) * 0.04
                let baseR: CGFloat = (700 - fi * 80) * spread
                let r = baseR * (1.0 + wobble)
                let alpha = (0.9 - Double(fi) * 0.15) * (0.4 + Double(level) * 0.6)

                let gradient = Gradient(colors: [
                    Color(hue: layerHue, saturation: 0.85, brightness: 1.0).opacity(alpha),
                    Color(hue: layerHue + 0.03, saturation: 0.75, brightness: 1.0).opacity(alpha * 0.25),
                    Color.clear
                ])

                // Draw in stretched coordinate system → circular gradient becomes oval
                context.drawLayer { ctx in
                    ctx.translateBy(x: cx, y: 0)
                    ctx.scaleBy(x: stretchX, y: 1.0)

                    let rect = CGRect(x: -r, y: -r * 0.3, width: r * 2, height: r * 2)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            gradient,
                            center: CGPoint(x: 0, y: 0),
                            startRadius: 0,
                            endRadius: r
                        )
                    )
                }
            }

            // Smoke wisps — also stretched
            for i in 0..<4 {
                let fi = Double(i)
                let phase = (flow * 0.4 + fi * 0.25).truncatingRemainder(dividingBy: 1.0)
                let drift = CGFloat(sin(phase * .pi * 2 + fi)) * 80
                let spread: CGFloat = 0.75 + level * 0.25
                let smokeR: CGFloat = (400 + CGFloat(phase) * 160) * spread
                let smokeAlpha = 0.06 * (0.3 + Double(level) * 0.7)
                let smokeHue = hue + fi * 0.015

                let gradient = Gradient(colors: [
                    Color(hue: smokeHue, saturation: 0.4, brightness: 1.0).opacity(smokeAlpha),
                    Color.clear
                ])

                context.drawLayer { ctx in
                    ctx.translateBy(x: cx + drift, y: 0)
                    ctx.scaleBy(x: stretchX * 0.8, y: 1.0)

                    let rect = CGRect(x: -smokeR, y: -smokeR * 0.2, width: smokeR * 2, height: smokeR * 2)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            gradient,
                            center: .zero,
                            startRadius: 0,
                            endRadius: smokeR * 0.7
                        )
                    )
                }
            }
        }
        .frame(width: viewWidth, height: viewHeight)
        .allowsHitTesting(false)
    }
}
