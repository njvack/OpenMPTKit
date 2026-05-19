import Clibopenmpt
import Foundation

public enum OpenMPTError: Error, LocalizedError {
    case loadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let msg): return "Failed to load module: \(msg)"
        }
    }
}

/// A loaded tracker module. Wraps an `openmpt_module *` and owns its lifetime.
public final class Module: @unchecked Sendable {
    private let handle: OpaquePointer

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        var errorCode: Int32 = OPENMPT_ERROR_OK
        var errorMessage: UnsafePointer<CChar>? = nil

        let ptr = data.withUnsafeBytes { buf -> OpaquePointer? in
            openmpt_module_create_from_memory2(
                buf.baseAddress, buf.count,
                nil, nil,           // log: silent
                nil, nil,           // error func: default
                &errorCode, &errorMessage,
                nil                 // no initial ctls
            )
        }

        if let msg = errorMessage {
            let description = String(cString: msg)
            openmpt_free_string(msg)
            throw OpenMPTError.loadFailed(description)
        }
        guard let ptr else {
            throw OpenMPTError.loadFailed("unknown error (code \(errorCode))")
        }
        handle = ptr
    }

    deinit {
        openmpt_module_destroy(handle)
    }

    // MARK: - Metadata

    private func metadata(_ key: String) -> String {
        guard let raw = openmpt_module_get_metadata(handle, key) else { return "" }
        defer { openmpt_free_string(raw) }
        return String(cString: raw)
    }

    public var title: String { metadata("title") }
    public var artist: String { metadata("artist") }
    public var type: String { metadata("type") }
    public var typeLong: String { metadata("type_long") }
    public var tracker: String { metadata("tracker") }
    public var date: String { metadata("date") }
    public var message: String { metadata("message") }

    // MARK: - Counts

    public var numChannels: Int { Int(openmpt_module_get_num_channels(handle)) }
    public var numOrders: Int { Int(openmpt_module_get_num_orders(handle)) }
    public var numPatterns: Int { Int(openmpt_module_get_num_patterns(handle)) }
    public var numInstruments: Int { Int(openmpt_module_get_num_instruments(handle)) }
    public var numSamples: Int { Int(openmpt_module_get_num_samples(handle)) }
    public var numSubsongs: Int { Int(openmpt_module_get_num_subsongs(handle)) }

    // MARK: - Named lists

    public var sampleNames: [String] {
        (0..<numSamples).map { i in
            guard let raw = openmpt_module_get_sample_name(handle, Int32(i)) else { return "" }
            defer { openmpt_free_string(raw) }
            return String(cString: raw)
        }
    }

    public var instrumentNames: [String] {
        (0..<numInstruments).map { i in
            guard let raw = openmpt_module_get_instrument_name(handle, Int32(i)) else { return "" }
            defer { openmpt_free_string(raw) }
            return String(cString: raw)
        }
    }

    public var subsongNames: [String] {
        (0..<numSubsongs).map { i in
            guard let raw = openmpt_module_get_subsong_name(handle, Int32(i)) else { return "" }
            defer { openmpt_free_string(raw) }
            return String(cString: raw)
        }
    }

    public func patternForOrder(_ order: Int) -> Int {
        Int(openmpt_module_get_order_pattern(handle, Int32(order)))
    }

    public func rowsInPattern(_ pattern: Int) -> Int {
        Int(openmpt_module_get_pattern_num_rows(handle, Int32(pattern)))
    }

    // MARK: - Playback

    /// Total duration of the (currently selected sub-)song in seconds.
    public var durationSeconds: Double {
        openmpt_module_get_duration_seconds(handle)
    }

    /// Current playback position in seconds.
    public var positionSeconds: Double {
        openmpt_module_get_position_seconds(handle)
    }

    /// Seek to the given position. Returns the actual position reached.
    @discardableResult
    public func seek(toSeconds seconds: Double) -> Double {
        openmpt_module_set_position_seconds(handle, seconds)
    }

    /// How many times the song should repeat after the first playthrough.
    /// `0` = play once (default), `-1` = loop forever.
    public func setRepeatCount(_ count: Int32) {
        _ = openmpt_module_set_repeat_count(handle, count)
    }

    /// Render `frameCount` stereo frames of float audio into the supplied
    /// (already-allocated) left/right buffers. Returns the number of frames
    /// actually rendered — `0` means end of song.
    public func renderStereo(
        sampleRate: Int32,
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) -> Int {
        openmpt_module_read_float_stereo(handle, sampleRate, frameCount, left, right)
    }
}
