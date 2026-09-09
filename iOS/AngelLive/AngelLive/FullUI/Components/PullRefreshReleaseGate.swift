import UIKit

/// A native refresh control can become armed while the finger is still down.
/// Delay both the request and its loading presentation until that drag ends.
@MainActor
final class PullRefreshReleaseGate {
    weak var scrollView: UIScrollView?

    enum GestureState { case held, released, cancelled }

    func waitForRelease() async -> Bool {
        await Self.waitForRelease { [weak self] in
            guard let scroll = self?.scrollView, scroll.window != nil else { return .cancelled }
            let pan = scroll.panGestureRecognizer.state
            if pan == .cancelled { return .cancelled }
            return scroll.isTracking || scroll.isDragging || pan == .began || pan == .changed
                ? .held : .released
        }
    }

    static func waitForRelease(readState: () -> GestureState) async -> Bool {
        while !Task.isCancelled {
            switch readState() {
            case .released: return true
            case .cancelled: return false
            case .held:
                // This loop exists only for an armed, held refresh. It neither
                // blocks the main actor nor installs a competing recognizer.
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return false }
            }
        }
        return false
    }
}
