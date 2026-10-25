// Spike: how fast can JUMP find the visible text of a window, through the
// accessibility tree and through OCR? Drives the "search visible text and jump
// to it" feasibility decision.
//
// Usage: jump-bench text <app name> [runs] [--dump <file>]
// Needs Accessibility access; the OCR half also needs Screen Recording.
// Nothing here launches, activates or sends input to the measured app.

import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

// MARK: - Accessibility text

nonisolated struct TextRun {
    var role: String
    var text: String
    var frame: CGRect
    var element: AXUIElement
}

nonisolated struct AXTextResult {
    var nodes = 0
    var runs: [TextRun] = []
    var webAreas: [AXUIElement] = []
    var truncated = false
}

/// Walks the window once, reading role, frame, children and the three text
/// attributes in a single round-trip per node, and keeps nodes that intersect
/// the window.
nonisolated func collectAXText(window: AXUIElement, windowFrame: CGRect,
                               deadline: ContinuousClock.Instant, nodeLimit: Int = 4000) -> AXTextResult {
    let names = ["AXRole", "AXPosition", "AXSize", "AXChildren", "AXValue", "AXTitle", "AXDescription"] as CFArray
    var result = AXTextResult()
    var stack: [AXUIElement] = [window]
    while let element = stack.popLast() {
        if result.nodes >= nodeLimit || ContinuousClock.now > deadline {
            result.truncated = true
            break
        }
        AXUIElementSetMessagingTimeout(element, 0.25)
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &values) == .success,
              let values = values as? [AnyObject], values.count == 7,
              let role = values[0] as? String
        else { continue }
        result.nodes += 1
        let frame = rect(values[1], values[2])
        if let frame, !frame.intersects(windowFrame), element != window { continue }
        if role == "AXWebArea" { result.webAreas.append(element) }
        for value in values[4...6] {
            guard let text = value as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result.runs.append(TextRun(role: role, text: trimmed, frame: frame ?? .null, element: element))
            break  // One string per node: value, else title, else description.
        }
        var children: [AXUIElement]
        if role == "AXTable" || role == "AXOutline" {
            var rows: CFTypeRef?
            AXUIElementCopyAttributeValue(element, "AXVisibleRows" as CFString, &rows)
            children = rows as? [AXUIElement] ?? []
        } else {
            children = values[3] as? [AXUIElement] ?? []
        }
        stack.append(contentsOf: children.reversed())
    }
    return result
}

nonisolated func rect(_ position: AnyObject, _ size: AnyObject) -> CGRect? {
    guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
          AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
    return CGRect(origin: point, size: extent)
}

/// Visible static text of a web area through one search-predicate query, then
/// one batched read per hit. `nil` when the engine rejects the query.
nonisolated func webStaticText(_ webArea: AXUIElement) -> (hits: Int, runs: [TextRun])? {
    let query: [String: Any] = [
        "AXDirection": "AXDirectionNext", "AXImmediateDescendantsOnly": false,
        "AXResultsLimit": -1, "AXVisibleOnly": true, "AXSearchKey": "AXStaticTextSearchKey",
    ]
    var value: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
        webArea, "AXUIElementsForSearchPredicate" as CFString, query as CFDictionary, &value) == .success,
        let hits = value as? [AXUIElement] else { return nil }
    let names = ["AXValue", "AXPosition", "AXSize"] as CFArray
    var runs: [TextRun] = []
    for hit in hits {
        var values: CFArray?
        if AXUIElementCopyMultipleAttributeValues(hit, names, [], &values) == .success,
           let values = values as? [AnyObject], values.count == 3,
           let text = values[0] as? String, !text.isEmpty {
            runs.append(TextRun(role: "AXStaticText", text: text, frame: rect(values[1], values[2]) ?? .null, element: hit))
        }
    }
    return (hits.count, runs)
}

/// Asks for the screen bounds of the first word of up to `limit` runs whose
/// text is the element's AXValue. Returns (supported, tried, total time).
nonisolated func probeWordBounds(_ runs: [TextRun], limit: Int = 40) -> (supported: Int, tried: Int, time: Duration) {
    var supported = 0
    var tried = 0
    var total = Duration.zero
    for run in runs where tried < limit {
        let words = run.text.split(whereSeparator: \.isWhitespace)
        guard words.count > 1, let word = words.dropFirst().first else { continue }
        // AXBoundsForRange counts UTF-16 units of the full AXValue.
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(run.element, "AXValue" as CFString, &value) == .success,
              let full = value as? String, let range = full.range(of: String(word)) else { continue }
        let nsRange = NSRange(range, in: full)
        var cfRange = CFRange(location: nsRange.location, length: nsRange.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { continue }
        tried += 1
        let start = ContinuousClock.now
        var bounds: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            run.element, "AXBoundsForRange" as CFString, parameter, &bounds)
        total += ContinuousClock.now - start
        var box = CGRect.zero
        if error == .success, let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
           AXValueGetValue(bounds as! AXValue, .cgRect, &box), box.width > 0,
           box.width < run.frame.width || run.frame.isNull {
            supported += 1
        }
    }
    return (supported, tried, total)
}

// MARK: - OCR

nonisolated struct OCRResult {
    var lines = 0
    var wordBoxes = 0
    var lineText: [String] = []
}

/// Legacy Vision API. Word boxes come from `boundingBox(for:)` on a word range.
nonisolated func recognizeVN(_ image: CGImage, level: VNRequestTextRecognitionLevel) throws -> OCRResult {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.usesLanguageCorrection = level == .accurate
    try VNImageRequestHandler(cgImage: image).perform([request])
    var result = OCRResult()
    for observation in request.results ?? [] {
        guard let candidate = observation.topCandidates(1).first else { continue }
        result.lines += 1
        result.lineText.append(candidate.string)
        let text = candidate.string
        if let space = text.firstIndex(of: " "),
           let box = try? candidate.boundingBox(for: text.startIndex..<space)?.boundingBox,
           box.width < observation.boundingBox.width * 0.95 {
            result.wordBoxes += 1
        }
    }
    return result
}

/// Swift Vision API (`RecognizeTextRequest`).
nonisolated func recognizeSwift(_ image: CGImage, fast: Bool) async throws -> OCRResult {
    var request = RecognizeTextRequest()
    request.recognitionLevel = fast ? .fast : .accurate
    request.usesLanguageCorrection = !fast
    let observations = try await request.perform(on: image)
    var result = OCRResult()
    for observation in observations {
        guard let candidate = observation.topCandidates(1).first else { continue }
        result.lines += 1
        let text = candidate.string
        if let space = text.firstIndex(of: " "),
           let box = candidate.boundingBox(for: text.startIndex..<space),
           box.boundingBox.width < observation.boundingBox.width * 0.95 {
            result.wordBoxes += 1
        }
    }
    return result
}

/// One ScreenCaptureKit window lookup plus capture, timed separately. Runs on
/// the main actor, which owns the window-server connection set up by NSApplication.
func captureWindow(pid: pid_t, frame: CGRect, nominal: Bool)
    async throws -> (image: CGImage, lookup: Duration, capture: Duration) {
    let lookupStart = ContinuousClock.now
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    let candidates = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
    guard let window = candidates.min(by: { distance($0.frame, frame) < distance($1.frame, frame) }) else {
        throw NSError(domain: "jump-bench", code: 1, userInfo: [NSLocalizedDescriptionKey: "no SCWindow for pid"])
    }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let lookup = ContinuousClock.now - lookupStart
    let scale = nominal ? 1 : CGFloat(filter.pointPixelScale)
    let configuration = SCStreamConfiguration()
    configuration.width = Int(window.frame.width * scale)
    configuration.height = Int(window.frame.height * scale)
    configuration.showsCursor = false
    let captureStart = ContinuousClock.now
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    return (image, lookup, ContinuousClock.now - captureStart)
}

nonisolated func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
    abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
}

// MARK: - Driver

nonisolated struct Samples {
    var values: [String: [Duration]] = [:]
    var order: [String] = []
    mutating func add(_ name: String, _ value: Duration) {
        if values[name] == nil { order.append(name) }
        values[name, default: []].append(value)
    }
    func report() -> String {
        order.map { name in
            // The first run of a process pays one-time costs (model loading, connections); reported apart.
            let all = values[name]!
            let s = all.count > 1 ? all.dropFirst().sorted() : all
            func ms(_ d: Duration) -> String { String(format: "%.1f", Double(d / .microseconds(1)) / 1000) }
            return "  \(name): median \(ms(s[s.count / 2])) ms, worst \(ms(s.last!)) ms (runs 2-\(all.count)); first run \(ms(all[0])) ms"
        }.joined(separator: "\n")
    }
}

func runTextBench(arguments: [String]) async {
    guard arguments.count >= 3 else {
        print("usage: jump-bench text <app name> [runs] [--dump <file>]")
        exit(2)
    }
    let name = arguments[2]
    setlinebuf(stdout)
    // SCContentFilter asserts (CGS_REQUIRE_INIT) unless the process holds a window-server connection.
    _ = NSApplication.shared
    let runs = arguments.count > 3 ? Int(arguments[3]) ?? 5 : 5
    var dumpPath: String?
    if let flag = arguments.firstIndex(of: "--dump") {
        guard flag + 1 < arguments.count else {
            print("usage: jump-bench text <app name> [runs] [--dump <file>]")
            exit(2)
        }
        dumpPath = arguments[flag + 1]
    }
    guard AXIsProcessTrusted() else { print("This terminal needs Accessibility access."); exit(1) }
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
        print("No running app named \(name)"); exit(1)
    }
    let pid = app.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    // Electron builds its tree only when asked, as JUMP does on activation; undone at the end.
    var manualSet = false
    var manualBefore: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, "AXManualAccessibility" as CFString, &manualBefore) != .success
        || (manualBefore as? Bool) != true {
        manualSet = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
        if manualSet { try? await Task.sleep(for: .seconds(1)) }
    }
    // `exit` skips `defer`, so early exits restore it explicitly.
    func restoreManualAccessibility() {
        if manualSet { AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanFalse) }
    }
    defer { restoreManualAccessibility() }

    var windowValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, "AXFocusedWindow" as CFString, &windowValue) == .success,
          let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
        print("\(name) has no focused window")
        restoreManualAccessibility()
        exit(1)
    }
    let window = windowValue as! AXUIElement
    var position: CFTypeRef?
    var size: CFTypeRef?
    AXUIElementCopyAttributeValue(window, "AXPosition" as CFString, &position)
    AXUIElementCopyAttributeValue(window, "AXSize" as CFString, &size)
    let windowFrame = position.flatMap { p in size.flatMap { rect(p, $0) } } ?? .infinite
    print("\(name) (\(app.bundleIdentifier ?? "?")), window \(windowFrame.integral)\(manualSet ? ", AXManualAccessibility turned on" : "")")

    var samples = Samples()
    var lastAX = AXTextResult()
    var lastWords = (supported: 0, tried: 0, time: Duration.zero)
    var lastWeb: (hits: Int, runs: [TextRun])?
    var lastWebWords = (supported: 0, tried: 0, time: Duration.zero)
    for run in 0..<runs {
        if run > 0 { try? await Task.sleep(for: .seconds(1)) }
        let start = ContinuousClock.now
        lastAX = collectAXText(window: window, windowFrame: windowFrame, deadline: .now.advanced(by: .seconds(5)))
        samples.add("AX text walk", ContinuousClock.now - start)
        lastWords = probeWordBounds(lastAX.runs)
        if lastWords.tried > 0 { samples.add("AXBoundsForRange per call", lastWords.time / lastWords.tried) }
        if let webArea = lastAX.webAreas.first {
            let webStart = ContinuousClock.now
            lastWeb = webStaticText(webArea)
            samples.add("web static-text predicate", ContinuousClock.now - webStart)
            if let lastWeb {
                lastWebWords = probeWordBounds(lastWeb.runs)
                if lastWebWords.tried > 0 { samples.add("web AXBoundsForRange per call", lastWebWords.time / lastWebWords.tried) }
            }
        }
    }
    let roleCounts = Dictionary(grouping: lastAX.runs, by: \.role).mapValues(\.count)
        .sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    let characters = lastAX.runs.reduce(0) { $0 + $1.text.count }
    print("AX: \(lastAX.nodes) nodes, \(lastAX.runs.count) text runs (\(characters) chars), truncated \(lastAX.truncated), web areas \(lastAX.webAreas.count)")
    print("  run roles: \(roleCounts)")
    print("  word bounds (AXBoundsForRange): \(lastWords.supported)/\(lastWords.tried) runs gave a word box")
    if let lastWeb {
        print("  web predicate: \(lastWeb.hits) hits, \(lastWeb.runs.count) with text (\(lastWeb.runs.reduce(0) { $0 + $1.text.count }) chars)")
        print("  web word bounds: \(lastWebWords.supported)/\(lastWebWords.tried) runs gave a word box")
    }
    if !lastAX.webAreas.isEmpty, lastWeb == nil { print("  web predicate: AXStaticTextSearchKey unsupported") }

    // OCR
    var ocrLines: [String] = []
    var lastImage: CGImage?
    if !CGPreflightScreenCaptureAccess() {
        print("OCR: Screen Recording not granted to this process; capture unmeasured")
    } else {
        var last: (fast: OCRResult, accurate: OCRResult, swiftFast: OCRResult, swiftAccurate: OCRResult, nominalFast: OCRResult)?
        var pixels = ""
        for run in 0..<runs {
            if run > 0 { try? await Task.sleep(for: .seconds(1)) }
            do {
                let shot = try await captureWindow(pid: pid, frame: windowFrame, nominal: false)
                samples.add("SC window lookup", shot.lookup)
                samples.add("SC capture (native scale)", shot.capture)
                pixels = "\(shot.image.width)x\(shot.image.height)"
                var t = ContinuousClock.now
                let fast = try recognizeVN(shot.image, level: .fast)
                samples.add("VN .fast", ContinuousClock.now - t)
                t = ContinuousClock.now
                let accurate = try recognizeVN(shot.image, level: .accurate)
                samples.add("VN .accurate", ContinuousClock.now - t)
                t = ContinuousClock.now
                let swiftFast = try await recognizeSwift(shot.image, fast: true)
                samples.add("RecognizeTextRequest .fast", ContinuousClock.now - t)
                t = ContinuousClock.now
                let swiftAccurate = try await recognizeSwift(shot.image, fast: false)
                samples.add("RecognizeTextRequest .accurate", ContinuousClock.now - t)
                let small = try await captureWindow(pid: pid, frame: windowFrame, nominal: true)
                samples.add("SC capture (1x)", small.capture)
                t = ContinuousClock.now
                let nominalFast = try recognizeVN(small.image, level: .fast)
                samples.add("VN .fast on 1x", ContinuousClock.now - t)
                last = (fast, accurate, swiftFast, swiftAccurate, nominalFast)
                ocrLines = accurate.lineText
                lastImage = shot.image
            } catch {
                print("OCR failed: \(error.localizedDescription)")
                break
            }
        }
        if let last {
            print("OCR on \(pixels): lines fast \(last.fast.lines), accurate \(last.accurate.lines), swift fast \(last.swiftFast.lines), swift accurate \(last.swiftAccurate.lines), fast@1x \(last.nominalFast.lines)")
            print("  first-word box narrower than line: fast \(last.fast.wordBoxes), accurate \(last.accurate.wordBoxes), swift accurate \(last.swiftAccurate.wordBoxes)")
        }
    }
    print("timings:\n\(samples.report())")

    if let dumpPath {
        var dump = "# AX runs\n" + lastAX.runs.map { "\($0.role)\t\($0.frame.integral)\t\($0.text.prefix(120))" }.joined(separator: "\n")
        dump += "\n# OCR accurate lines\n" + ocrLines.joined(separator: "\n") + "\n"
        try? dump.write(toFile: dumpPath, atomically: true, encoding: .utf8)
        if let lastImage, let png = NSBitmapImageRep(cgImage: lastImage).representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dumpPath + ".png"))
        }
    }
}
