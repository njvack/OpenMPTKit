import Foundation
import Testing
@testable import OpenMPTKit

// These tests exercise the Swift binding layer only — string marshalling,
// error propagation, lifetime, Sendable conformance. We trust libopenmpt
// to parse and render correctly; we do not re-test that here.

private func sampleModURL(_ name: String = "1PAT.MOD") -> URL {
    // thisFile = .../src/OpenMPTKit/Tests/OpenMPTKitTests/ModuleTests.swift
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // OpenMPTKitTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // OpenMPTKit/
        .deletingLastPathComponent()  // src/
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("sample_mods")
        .appendingPathComponent(name)
}

// MARK: - Error handling

@Test func garbageDataThrowsOpenMPTError() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("openmptkit-\(UUID().uuidString).bin")
    try Data(repeating: 0x42, count: 4096).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    do {
        _ = try Module(url: tmp)
        Issue.record("expected OpenMPTError.loadFailed")
    } catch let OpenMPTError.loadFailed(message) {
        // We don't care what the message says, only that one came through
        // from the C layer and was properly freed (i.e. we didn't crash).
        #expect(!message.isEmpty)
    }
}

@Test func emptyFileThrowsOpenMPTError() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("openmptkit-empty-\(UUID().uuidString).bin")
    try Data().write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    #expect(throws: OpenMPTError.self) {
        _ = try Module(url: tmp)
    }
}

@Test func missingFileThrowsFoundationError() {
    let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).mod")
    // Foundation's Data(contentsOf:) throws first, before we ever reach the
    // C layer. We just need to confirm something is thrown.
    #expect(throws: (any Error).self) {
        _ = try Module(url: url)
    }
}

// MARK: - String / array marshalling

@Test func metadataAccessorsNeverCrash() throws {
    let mod = try Module(url: sampleModURL())
    // Each accessor allocates a C string and frees it. Hammer them to
    // catch any leaks-of-pointer or double-free regressions under ASan.
    for _ in 0..<32 {
        _ = mod.title
        _ = mod.artist
        _ = mod.type
        _ = mod.typeLong
        _ = mod.tracker
        _ = mod.date
        _ = mod.message
    }
}

@Test func namedListsMatchDeclaredCounts() throws {
    let mod = try Module(url: sampleModURL())
    #expect(mod.sampleNames.count == mod.numSamples)
    #expect(mod.instrumentNames.count == mod.numInstruments)
    #expect(mod.subsongNames.count == mod.numSubsongs)
}

// MARK: - Render API contract

@Test func renderStereoRespectsRequestedFrameCount() throws {
    let mod = try Module(url: sampleModURL())
    let frames = 1024
    var left = [Float](repeating: 0, count: frames)
    var right = [Float](repeating: 0, count: frames)

    let produced = left.withUnsafeMutableBufferPointer { l in
        right.withUnsafeMutableBufferPointer { r in
            mod.renderStereo(
                sampleRate: 48_000,
                frameCount: frames,
                left: l.baseAddress!,
                right: r.baseAddress!
            )
        }
    }

    #expect(produced >= 0)
    #expect(produced <= frames)
}

@Test func renderStereoWithZeroFramesIsHarmless() throws {
    let mod = try Module(url: sampleModURL())
    var dummy: Float = 0
    let produced = withUnsafeMutablePointer(to: &dummy) { ptr in
        mod.renderStereo(sampleRate: 48_000, frameCount: 0, left: ptr, right: ptr)
    }
    #expect(produced == 0)
}

// MARK: - Current state accessors

@Test func currentStateAccessorsReturnSaneTypes() throws {
    let mod = try Module(url: sampleModURL())
    // We don't claim specific values — just that the accessors are wired
    // up to their C counterparts and return in-range types.
    #expect(mod.currentOrder >= 0)
    #expect(mod.currentRow >= 0)
    #expect(mod.currentSpeed >= 0)
    #expect(mod.currentTempo >= 0)
    #expect(mod.currentPlayingChannels >= 0)
    #expect(mod.estimatedBPM >= 0)
    _ = mod.currentPattern  // can be -1 for unmapped orders; just exercise it
}

// MARK: - Pattern data accessors

@Test func patternGeometryAccessors() throws {
    let mod = try Module(url: sampleModURL())
    try #require(mod.numPatterns > 0)
    let pat = 0
    #expect(mod.rowsInPattern(pat) > 0)
    #expect(mod.rowsPerBeat(in: pat) >= 0)
    #expect(mod.rowsPerMeasure(in: pat) >= 0)
    _ = mod.patternName(pat)  // may be empty; just exercise marshalling
}

@Test func cellAccessorsForEveryField() throws {
    let mod = try Module(url: sampleModURL())
    try #require(mod.numPatterns > 0 && mod.numChannels > 0)
    let pat = 0
    try #require(mod.rowsInPattern(pat) > 0)

    for field in [Module.CellField.note, .instrument, .volumeEffect,
                  .effect, .volume, .parameter] {
        _ = mod.cellRaw(pattern: pat, row: 0, channel: 0, field: field)
        _ = mod.cellFormatted(pattern: pat, row: 0, channel: 0, field: field)
    }
}

@Test func cellFormattedAndHighlightAgreeOnWidth() throws {
    let mod = try Module(url: sampleModURL())
    try #require(mod.numPatterns > 0 && mod.numChannels > 0)
    try #require(mod.rowsInPattern(0) > 0)

    let formatted = mod.cellFormatted(pattern: 0, row: 0, channel: 0, width: 16, pad: true)
    let highlight = mod.cellHighlight(pattern: 0, row: 0, channel: 0, width: 16, pad: true)
    // libopenmpt guarantees the two strings are character-aligned.
    #expect(formatted.count == highlight.count)
}

// MARK: - Seek / position

@Test func seekReflectedInPositionAccessor() throws {
    let mod = try Module(url: sampleModURL())
    let reached = mod.seek(toSeconds: 0.0)
    // Whatever libopenmpt landed on, positionSeconds should agree.
    #expect(abs(mod.positionSeconds - reached) < 0.001)
}

// MARK: - Lifetime / Sendable

@Test func moduleCanBeReleasedWithoutCrash() throws {
    // Create and drop in a loop; deinit must call openmpt_module_destroy
    // exactly once per instance.
    for _ in 0..<8 {
        let mod = try Module(url: sampleModURL())
        _ = mod.numChannels
    }
}

@Test func moduleCrossesConcurrencyBoundary() async throws {
    // The binding marks Module as @unchecked Sendable so it can be handed
    // to other tasks/actors. This test would fail to compile if that ever
    // regressed.
    let mod = try Module(url: sampleModURL())
    let channels = await Task.detached { mod.numChannels }.value
    #expect(channels == mod.numChannels)
}
