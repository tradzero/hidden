import Foundation

/// Empirical macOS 27 layout probe, not an AppKit visibility guarantee.
/// All callbacks run on the main queue. The scheduler is injectable for race tests.
final class CollapseLengthCalibrator {
    /// Empirical conservative ceiling for seven-item groups, in logical points.
    /// Seek enough combined span rather than the current foreground menu's cliff.
    static func conservativeUpperBound(screenWidths: [CGFloat]) -> CGFloat {
        let widths = screenWidths.filter { $0.isFinite && $0 > 0 }
        guard let narrowest = widths.min(), let widest = widths.max() else { return 300 }
        return max(40, min(narrowest / 4, widest / 7 + 64))
    }

    struct Geometry {
        let edge: CGFloat
        let anchor: CGFloat
        let context: String
        var offset: CGFloat { edge - anchor }

        func isStable(comparedTo other: Geometry) -> Bool {
            context == other.context && abs(edge - other.edge) <= 1
                && abs(anchor - other.anchor) <= 1
        }
    }

    enum Outcome {
        case applied(CGFloat)
        case unavailable
        case unsettled
    }

    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void
    private let read: () -> Geometry?
    private let write: (CGFloat) -> Void
    private let schedule: Scheduler
    private var generation = 0
    private var completion: ((Outcome) -> Void)?
    private var baseline: Geometry?
    private var expanded: CGFloat = 20
    private var low: CGFloat = 20
    private var high: CGFloat = 20
    private var iterations = 0

    init(read: @escaping () -> Geometry?, write: @escaping (CGFloat) -> Void,
         schedule: @escaping Scheduler = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        self.read = read
        self.write = write
        self.schedule = schedule
    }

    func cancel() {
        generation += 1
        completion = nil
        baseline = nil
    }

    func start(expanded: CGFloat, upperBound: CGFloat, cached: CGFloat?,
               completion: @escaping (Outcome) -> Void) {
        cancel()
        let token = generation
        self.completion = completion
        self.expanded = expanded
        low = expanded
        high = upperBound
        iterations = 0
        write(expanded)
        sample(token: token) { [weak self] geometry in
            guard let self = self else { return }
            guard let geometry = geometry else { self.finish(.unsettled); return }
            self.baseline = geometry
            if let cached = cached, cached > expanded, cached <= upperBound {
                self.probe(cached, token: token) { [weak self] laidOut in
                    guard let self = self else { return }
                    if laidOut { self.finish(.applied(cached)) }
                    else { self.search(token: token) }
                }
            } else {
                self.search(token: token)
            }
        }
    }

    private func search(token: Int) {
        guard high - low > 8, iterations < 12 else {
            guard low > expanded else { finish(.unavailable); return }
            // Leave headroom below the observed cliff, then verify that final value.
            let candidate = max(expanded + 1, low - 8)
            probe(candidate, token: token) { [weak self] laidOut in
                self?.finish(laidOut ? .applied(candidate) : .unsettled)
            }
            return
        }
        iterations += 1
        let candidate = floor((low + high) / 2)
        probe(candidate, token: token) { [weak self] laidOut in
            guard let self = self else { return }
            if laidOut { self.low = candidate } else { self.high = candidate }
            self.search(token: token)
        }
    }

    private func probe(_ length: CGFloat, token: Int, result: @escaping (Bool) -> Void) {
        guard generation == token, completion != nil else { return }
        write(length)
        sample(token: token) { [weak self] geometry in
            guard let self = self, let baseline = self.baseline else { return }
            guard let geometry = geometry, geometry.context == baseline.context,
                  abs(geometry.anchor - baseline.anchor) <= 24 else {
                self.finish(.unsettled)
                return
            }
            // The arrow-facing edge stays pinned while the separator occupies space.
            // This tolerance accommodates measured status-window padding, not an API limit.
            result(abs(geometry.offset - baseline.offset) <= 24)
        }
    }

    private func sample(token: Int, previous: Geometry? = nil, attempts: Int = 6,
                        result: @escaping (Geometry?) -> Void) {
        schedule(0.12) { [weak self] in
            guard let self = self, self.generation == token, self.completion != nil else { return }
            let current = self.read()
            if let current = current, let previous = previous,
               current.isStable(comparedTo: previous) {
                result(current)
            } else if attempts > 1 {
                self.sample(token: token, previous: current, attempts: attempts - 1, result: result)
            } else {
                result(nil)
            }
        }
    }

    private func finish(_ outcome: Outcome) {
        let callback = completion
        completion = nil
        baseline = nil
        callback?(outcome)
    }
}
