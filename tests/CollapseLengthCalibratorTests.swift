import Foundation

// Deterministic virtual runloop: race tests exercise the production coordinator.
final class Fixture {
    var queue: [() -> Void] = []
    var writes: [CGFloat] = []
    var length: CGFloat = 20
    var cutoff: CGFloat = 629
    var geometryAvailable = true
    var context = "display-a"
    var anchor: CGFloat = 1200
    var outcome: CollapseLengthCalibrator.Outcome?
    lazy var calibrator = CollapseLengthCalibrator(read: { [unowned self] in
        guard self.geometryAvailable else { return nil }
        let offset: CGFloat = self.length <= self.cutoff ? -8 : self.length
        return .init(edge: self.anchor + offset, anchor: self.anchor, context: self.context)
    }, write: { [unowned self] value in
        self.length = value
        self.writes.append(value)
    }, schedule: { [unowned self] _, action in self.queue.append(action) })

    func start(cached: CGFloat? = nil) {
        outcome = nil
        calibrator.start(expanded: 20, upperBound: 3600, cached: cached) { [unowned self] in self.outcome = $0 }
    }
    func tick() { if !queue.isEmpty { queue.removeFirst()() } }
    func drain() {
        var count = 0
        while !queue.isEmpty { tick(); count += 1; precondition(count < 300, "unbounded probing") }
    }
    var applied: CGFloat? { if case .applied(let value) = outcome { return value }; return nil }
}

@main
enum CalibrationTests {
    static func main() {
        let boundary = Fixture()
        boundary.start(); boundary.drain()
        precondition(boundary.applied != nil && boundary.applied! <= 629 && boundary.applied! >= 605)
        precondition(boundary.length == boundary.applied)

        let cache = Fixture()
        cache.start(cached: 600); cache.drain()
        precondition(cache.applied == 600 && cache.writes == [20, 600])

        let staleCache = Fixture()
        staleCache.cutoff = 310
        staleCache.start(cached: 600); staleCache.drain()
        precondition(staleCache.applied != nil && staleCache.applied! <= 310)

        let cancelled = Fixture()
        cancelled.start(); cancelled.tick(); cancelled.tick()
        cancelled.calibrator.cancel()
        let writeCount = cancelled.writes.count
        cancelled.length = 20 // User expands while a probe is in flight.
        cancelled.drain()
        precondition(cancelled.writes.count == writeCount && cancelled.length == 20 && cancelled.outcome == nil)

        let restarted = Fixture()
        restarted.start(); restarted.tick(); restarted.tick()
        restarted.context = "display-b"; restarted.cutoff = 300
        restarted.start(); restarted.drain()
        precondition(restarted.applied != nil && restarted.applied! <= 300)

        let missing = Fixture()
        missing.geometryAvailable = false; missing.start(); missing.drain()
        if case .unsettled = missing.outcome {} else { fatalError("missing geometry was cached") }
        missing.geometryAvailable = true; missing.start(); missing.drain()
        precondition(missing.applied != nil)

        let unavailable = Fixture()
        unavailable.cutoff = 20; unavailable.start(); unavailable.drain()
        if case .unavailable = unavailable.outcome {} else { fatalError("no fit reported as collapsed") }

        let moved = Fixture()
        moved.start(); moved.tick(); moved.tick()
        moved.anchor += 100; moved.drain()
        if case .unsettled = moved.outcome {} else { fatalError("changed anchor accepted") }

        let changedContext = Fixture()
        changedContext.start(); changedContext.tick(); changedContext.tick()
        changedContext.context = "display-b"; changedContext.drain()
        if case .unsettled = changedContext.outcome {} else { fatalError("mixed display samples accepted") }

        let bound = CollapseLengthCalibrator.conservativeUpperBound(screenWidths: [1920, 1920])
        precondition(bound < 400 && bound > 1920 / 7)
        precondition(CollapseLengthCalibrator.conservativeUpperBound(screenWidths: [3008, 1800]) == 450)
        precondition(CollapseLengthCalibrator.conservativeUpperBound(screenWidths: []) == 300)

        print("PASS: 12 calibration tests (boundary, cache, stale cache, cancellation, restart, missing geometry, no fit, anchor change, context change, conservative display bounds)")
    }
}
