import SwiftUI
import UIKit

/// FullUI-only presentation. Native scroll views own the refresh threshold.
struct LiquidRefreshIndicator: View {
    let pullDistance: CGFloat
    let isRefreshing: Bool
    var refreshCycle: Int = 0
    var accessibilityTitle = "正在刷新"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var anchor: LiquidRefreshAnchor?
    @State private var startedAt: Date?
    @State private var completedAt: Date?
    @State private var initialPull: CGFloat = 0
    @State private var observedCycle: Int?
    @State private var pullState = LiquidRefreshPullState()

    private var progress: CGFloat { min(max((pullDistance - 8) / 100, 0), 1) }

    var body: some View {
        Color.clear
            .frame(height: 120)
            .background(LiquidRefreshAnchorProbe(anchor: $anchor))
            .overlay(alignment: .topLeading) {
                if let anchor {
                    TimelineView(.animation(paused: startedAt == nil || reduceMotion || scenePhase != .active)) { timeline in
                        let pose = LiquidRefreshPose.resolve(
                            now: timeline.date, startedAt: startedAt, completedAt: completedAt,
                            initialPull: initialPull,
                            pull: pullState.visibleProgress(for: pullDistance),
                            reducedMotion: reduceMotion
                        )
                        LiquidRefreshArtwork(
                            pose: pose,
                            attached: anchor.attached && !reduceMotion,
                            reducedMotion: reduceMotion,
                            darkAppearance: colorScheme == .dark
                        )
                        .frame(width: 120, height: 120)
                    }
                    .offset(x: anchor.point.x - 60, y: anchor.point.y)
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isRefreshing ? accessibilityTitle : "下拉刷新")
            .accessibilityHidden(!isRefreshing)
            .onChange(of: pullDistance) { _, distance in
                pullState.observe(distance: distance, refreshPresented: isRefreshing || startedAt != nil)
            }
            .onChange(of: startedAt) { _, start in
                // Read the current drag after the return task completes, not
                // the distance its closure captured before suspending.
                pullState.observe(distance: pullDistance, refreshPresented: isRefreshing || start != nil)
            }
            .task(id: RefreshTrigger(cycle: refreshCycle, active: isRefreshing)) {
                let newCycle = observedCycle != nil && observedCycle != refreshCycle
                observedCycle = refreshCycle
                if isRefreshing || newCycle {
                    initialPull = progress
                    pullState.consume()
                    completedAt = nil
                    startedAt = .now
                }
                if !isRefreshing, let startedAt {
                    let completion = Date.now
                    completedAt = completion
                    // Only presentation is held: fast requests must still show
                    // the neck break and a detached drop before retracting.
                    let end = max(completion.timeIntervalSinceReferenceDate,
                                  startedAt.timeIntervalSinceReferenceDate + 0.56) + 0.48
                    let remaining = max(0, end - Date.now.timeIntervalSinceReferenceDate)
                    do { try await Task.sleep(for: .seconds(remaining)) }
                    catch { return }
                    self.startedAt = nil
                    completedAt = nil
                }
            }
            .onDisappear {
                startedAt = nil
                completedAt = nil
                observedCycle = nil
                pullState = LiquidRefreshPullState()
            }
    }

    private struct RefreshTrigger: Equatable {
        let cycle: Int
        let active: Bool
    }
}

/// A held drag belongs to the refresh it triggered. Once consumed, it must
/// return to rest before it can draw a new pull preview.
struct LiquidRefreshPullState {
    private(set) var waitsForRest = false

    mutating func consume() {
        waitsForRest = true
    }

    mutating func observe(distance: CGFloat, refreshPresented: Bool) {
        guard !refreshPresented, distance <= 1 else { return }
        waitsForRest = false
    }

    func visibleProgress(for distance: CGFloat) -> CGFloat {
        waitsForRest ? 0 : min(max((distance - 8) / 100, 0), 1)
    }
}

/// Pinch first, then let the drop fall. Radius stays stable until the final
/// part of the return, avoiding a shrinking bead on a long string.
struct LiquidRefreshPose {
    var progress: CGFloat
    var separation: CGFloat
    var centerY: CGFloat
    var loading: CGFloat
    var rotation: Double

    static func resolve(
        now: Date, startedAt: Date?, completedAt: Date?,
        initialPull: CGFloat, pull: CGFloat, reducedMotion: Bool
    ) -> Self {
        guard let start = startedAt else {
            return .init(progress: pull, separation: 0, centerY: -8 + 32 * pull, loading: 0, rotation: 0)
        }
        if reducedMotion {
            return .init(progress: completedAt == nil ? 1 : 0, separation: 1, centerY: 26, loading: 1, rotation: 0)
        }
        let elapsed = max(0, now.timeIntervalSince(start))
        if elapsed < 0.38 {
            let pinch = smooth(clamp(elapsed / 0.18))
            let fall = smooth(clamp((elapsed - 0.10) / 0.28))
            let fromY = -8 + 32 * initialPull
            return .init(
                progress: initialPull + (1 - initialPull) * fall,
                separation: pinch,
                centerY: fromY + (44 - fromY) * fall,
                loading: smooth(clamp((elapsed - 0.22) / 0.16)), rotation: 0
            )
        }
        let rotation = max(0, elapsed - 0.38) * 2 * Double.pi
        if let completedAt {
            let returnStart = max(0.56, completedAt.timeIntervalSince(start))
            if elapsed >= returnStart {
                let t = clamp((elapsed - returnStart) / 0.48)
                let y = 44 - 52 * smooth(t)
                return .init(
                    progress: 1 - smooth(clamp((t - 0.65) / 0.35)),
                    separation: smooth(clamp((y - 3) / 19)),
                    centerY: y, loading: 1 - smooth(clamp(t / 0.24)), rotation: rotation
                )
            }
        }
        return .init(progress: 1, separation: 1, centerY: 44, loading: 1, rotation: rotation)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
    private static func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
}

/// A small drawing surface avoids filtering the entire screen to merge liquid.
private struct LiquidRefreshArtwork: View {
    let pose: LiquidRefreshPose
    let attached: Bool
    let reducedMotion: Bool
    let darkAppearance: Bool

    var body: some View {
        Canvas { context, size in
            let p = pose.progress
            let s = pose.separation
            let x = size.width / 2
            let radius = 6 + 6 * p
            let y = reducedMotion ? 26 : pose.centerY + (attached ? 0 : 22)
            let rx = radius * (1 - 0.04 * p * (1 - s))
            let drop = Path(ellipseIn: CGRect(x: x - rx, y: y - radius, width: rx * 2, height: radius * 2))
            context.opacity = min(p * 5, 1)

            if attached && s < 0.999 && y > radius * 0.65 && p > 0.015 {
                let base = (12 - 2 * p) * (1 - s)
                let thin = (3.8 - 2 * p) * pow(1 - s, 1.6)
                let join = y - radius * 0.65
                let waist = join * 0.48
                let shoulder = rx * 0.78 * (1 - s)
                var neck = Path()
                neck.move(to: CGPoint(x: x - base, y: 0))
                neck.addCurve(to: CGPoint(x: x - thin, y: waist),
                              control1: CGPoint(x: x - base * 0.45, y: waist * 0.3),
                              control2: CGPoint(x: x - thin, y: waist * 0.7))
                neck.addCurve(to: CGPoint(x: x - shoulder, y: join + 3),
                              control1: CGPoint(x: x - thin, y: waist + (join - waist) * 0.6),
                              control2: CGPoint(x: x - shoulder, y: join))
                neck.addLine(to: CGPoint(x: x + shoulder, y: join + 3))
                neck.addCurve(to: CGPoint(x: x + thin, y: waist),
                              control1: CGPoint(x: x + shoulder, y: join),
                              control2: CGPoint(x: x + thin, y: waist + (join - waist) * 0.6))
                neck.addCurve(to: CGPoint(x: x + base, y: 0),
                              control1: CGPoint(x: x + thin, y: waist * 0.7),
                              control2: CGPoint(x: x + base * 0.45, y: waist * 0.3))
                neck.closeSubpath()
                context.fill(neck, with: .color(.black))
            }
            context.fill(drop, with: .color(.black))
            if darkAppearance {
                context.stroke(drop, with: .color(.white.opacity(0.16 * s)), lineWidth: 0.5)
            }
            if pose.loading > 0 {
                context.opacity *= pose.loading
                let ringRect = CGRect(x: x - 6, y: y - 6, width: 12, height: 12)
                context.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.2)), lineWidth: 1.4)
                var arc = Path()
                arc.addArc(center: CGPoint(x: x, y: y), radius: 6,
                           startAngle: .radians(pose.rotation), endAngle: .radians(pose.rotation + 4.2), clockwise: false)
                context.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
    }
}

private struct LiquidRefreshAnchor: Equatable {
    let point: CGPoint
    let attached: Bool
}

/// Reads the containing window, never another scene's key window. UIKit does
/// not expose the cutout outline. Overlap inside the safe-area margin connects
/// common sensor housings without drawing a fake island.
private struct LiquidRefreshAnchorProbe: UIViewRepresentable {
    @Binding var anchor: LiquidRefreshAnchor?

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.publish = { value in
            if anchor != value { anchor = value }
        }
        view.scheduleMeasurement()
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: ()) {
        view.pending?.cancel()
        view.publish = nil
    }

    final class ProbeView: UIView {
        var publish: ((LiquidRefreshAnchor) -> Void)?
        var pending: Task<Void, Never>?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleMeasurement()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleMeasurement()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            scheduleMeasurement()
        }

        func scheduleMeasurement() {
            pending?.cancel()
            pending = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, let window, bounds.width > 0 else { return }
                let top = window.safeAreaInsets.top
                let frameInWindow = convert(bounds, to: window)
                let fullWidth = abs(frameInWindow.width - window.bounds.width) < 2
                let attached = traitCollection.userInterfaceIdiom == .phone
                    && window.bounds.height > window.bounds.width && top >= 44 && fullWidth
                let windowPoint = CGPoint(
                    x: attached ? window.bounds.midX : frameInWindow.midX,
                    y: attached ? top - 20 : max(top, frameInWindow.minY) + 8
                )
                publish?(LiquidRefreshAnchor(point: convert(windowPoint, from: window), attached: attached))
            }
        }
    }
}
