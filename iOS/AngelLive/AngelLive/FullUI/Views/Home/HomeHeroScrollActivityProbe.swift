import SwiftUI
import UIKit

/// Observes the carousel's actual scrolling lifecycle on iOS 17 and later.
/// It does not replace SwiftUI's scroll delegate or add a competing gesture.
struct HomeHeroScrollActivityProbe: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> HomeHeroScrollActivityView {
        HomeHeroScrollActivityView(onChange: onChange)
    }

    func updateUIView(_ uiView: HomeHeroScrollActivityView, context: Context) {
        uiView.onChange = onChange
    }

    static func dismantleUIView(_ uiView: HomeHeroScrollActivityView, coordinator: ()) {
        uiView.stopObserving()
    }
}

final class HomeHeroScrollActivityView: UIView {
    var onChange: (Bool) -> Void

    private weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var displayLink: CADisplayLink?
    private var previousOffset: CGPoint = .zero
    private var stationaryFrames = 0
    private var reportedActivity: Bool?
    private var originalBounces = true

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            stopObserving()
            return
        }
        var ancestor = superview
        while let view = ancestor {
            if let enclosing = view as? UIScrollView {
                startObserving(enclosing)
                return
            }
            ancestor = view.superview
        }
    }

    private func startObserving(_ enclosing: UIScrollView) {
        guard enclosing !== scrollView else { return }
        stopObserving()
        scrollView = enclosing
        originalBounces = enclosing.bounces
        // The neighboring page is the edge of the rendering window, not the
        // end of the feed. A held drag must never pull empty canvas into view.
        enclosing.bounces = false
        previousOffset = enclosing.contentOffset
        enclosing.panGestureRecognizer.addTarget(self, action: #selector(panChanged))
        offsetObservation = enclosing.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            // UIKit changes this view's contentOffset on the main thread.
            // Only wake sampling here; never mutate SwiftUI state during layout.
            MainActor.assumeIsolated { self?.startSampling() }
        }
        startSampling()
    }

    func stopObserving() {
        offsetObservation = nil
        displayLink?.invalidate()
        displayLink = nil
        if let scrollView {
            scrollView.panGestureRecognizer.removeTarget(self, action: #selector(panChanged))
            scrollView.bounces = originalBounces
        }
        scrollView = nil
        reportedActivity = nil
    }

    @objc private func panChanged() {
        // The target runs during touch handling, including cancellation.
        if let scrollView, scrollView.isTracking || scrollView.isDragging {
            report(true)
        }
        startSampling()
    }

    private func startSampling() {
        stationaryFrames = 0
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    fileprivate func sample() {
        guard let scrollView, window != nil else {
            stopObserving()
            return
        }
        let moving = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
            || scrollView.contentOffset != previousOffset
        previousOffset = scrollView.contentOffset
        stationaryFrames = moving ? 0 : stationaryFrames + 1
        if moving {
            report(true)
        } else if stationaryFrames >= 2 {
            // Wait for the final rendered offset, including programmatic
            // animation. No fixed delay guesses how long a gesture lasts.
            displayLink?.invalidate()
            displayLink = nil
            report(false)
        }
    }

    private func report(_ active: Bool) {
        guard reportedActivity != active else { return }
        reportedActivity = active
        onChange(active)
    }

    @MainActor
    private final class DisplayLinkTarget: NSObject {
        weak var view: HomeHeroScrollActivityView?

        init(_ view: HomeHeroScrollActivityView) {
            self.view = view
        }

        @objc func tick() {
            view?.sample()
        }
    }
}
