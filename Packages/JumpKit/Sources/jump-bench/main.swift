// Measures how long JUMP takes to scan an app's focused window, and where the
// time goes, so latency work is driven by numbers.
//
// Usage: swift run -c release --package-path Packages/JumpKit jump-bench <app name> [runs] [--warm]
// The calling terminal needs Accessibility access.
//
// Runs are spaced by a second by default: apps drop their accessibility caches
// between real hotkey presses, and back-to-back scans (`--warm`) look ~30% faster
// than what users get.

import AppKit
import ApplicationServices
import JumpKit
import Synchronization

nonisolated final class CallStats: Sendable {
    private struct Totals {
        var count = 0
        var duration = Duration.zero
    }

    private let totals = Mutex<[String: Totals]>([:])
    private let slowest = Mutex<[(Duration, String)]>([])
    private let roles = Mutex<[String: Int]>([:])

    func recordAttributes(_ duration: Duration, role: String) {
        roles.withLock { $0[role, default: 0] += 1 }
        slowest.withLock { list in
            list.append((duration, role))
            list.sort { $0.0 > $1.0 }
            if list.count > 5 { list.removeLast() }
        }
    }

    func measure<T>(_ name: String, _ body: () -> T) -> T {
        let start = ContinuousClock.now
        let result = body()
        let elapsed = ContinuousClock.now - start
        totals.withLock { $0[name, default: Totals()].count += 1; $0[name, default: Totals()].duration += elapsed }
        return result
    }

    func reset() {
        totals.withLock { $0 = [:] }
        slowest.withLock { $0 = [] }
        roles.withLock { $0 = [:] }
    }

    func rolesReport() -> String {
        roles.withLock { $0.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") }
    }

    func slowestReport() -> String {
        slowest.withLock { list in
            list.map { "  \(String(format: "%.2f", Double($0.0 / .microseconds(1)) / 1000)) ms  \($0.1)" }
                .joined(separator: "\n")
        }
    }

    func report() -> String {
        totals.withLock { totals in
            totals.sorted { $0.key < $1.key }.map { name, t in
                let ms = Double(t.duration / .microseconds(1)) / 1000
                return "  \(name): \(t.count) calls, \(String(format: "%.1f", ms)) ms"
            }.joined(separator: "\n")
        }
    }
}

let stats = CallStats()

/// Wraps the live node and times every AX round-trip.
nonisolated struct TimedNode: AccessibilityNode {
    let base: AXNode
    func attributes(prefetchingChildren: Bool) -> NodeAttributes? {
        let start = ContinuousClock.now
        let result = stats.measure("attributes") { base.attributes(prefetchingChildren: prefetchingChildren) }
        stats.recordAttributes(ContinuousClock.now - start, role: result?.role ?? "<gone>")
        return result
    }
    func actions() -> [String] { stats.measure("actions") { base.actions() } }
    func children(role: String) -> [TimedNode] {
        stats.measure("children") { base.children(role: role) }.map(TimedNode.init)
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: jump-bench <app name> [runs]")
    exit(2)
}
guard AXIsProcessTrusted() else {
    print("This terminal needs Accessibility access.")
    exit(1)
}
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == arguments[1] }) else {
    print("No running app named \(arguments[1])")
    exit(1)
}
let runs = arguments.count > 2 ? Int(arguments[2]) ?? 10 : 10
let warm = arguments.contains("--warm")

let appElement = AXNode(AXUIElementCreateApplication(app.processIdentifier))
var windowValue: CFTypeRef?
guard AXUIElementCopyAttributeValue(appElement.element, "AXFocusedWindow" as CFString, &windowValue) == .success,
      let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID()
else {
    print("\(arguments[1]) has no focused window")
    exit(1)
}
let window = AXNode(windowValue as! AXUIElement)

var durations: [Duration] = []
var lastResult: ScanResult<TimedNode>?
for run in 0..<runs {
    if !warm, run > 0 { Thread.sleep(forTimeInterval: 1) }
    stats.reset()
    let start = ContinuousClock.now
    lastResult = ElementScanner().scan(root: TimedNode(base: window), deadline: .now.advanced(by: .seconds(5)))
    durations.append(ContinuousClock.now - start)
}

let sorted = durations.sorted()
func ms(_ d: Duration) -> String { String(format: "%.1f ms", Double(d / .microseconds(1)) / 1000) }
print("\(arguments[1]): \(lastResult!.elements.count) hints, \(lastResult!.visitedCount) nodes, truncated: \(lastResult!.isTruncated)")
print("scan over \(runs) \(warm ? "back-to-back" : "spaced") runs: min \(ms(sorted.first!)), median \(ms(sorted[sorted.count / 2])), max \(ms(sorted.last!))")
print("last run breakdown:\n\(stats.report())")
print("slowest attribute reads (last run):\n\(stats.slowestReport())")
print("visited roles (last run): \(stats.rolesReport())")
if arguments.contains("--targets") {
    for element in lastResult!.elements {
        print("  target \(element.role) \(element.frame.integral)")
    }
}

