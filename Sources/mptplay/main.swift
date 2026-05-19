import AVFoundation
import Foundation
import OpenMPTKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: mptplay <module-file>\n", stderr)
    exit(1)
}

let url = URL(filePath: CommandLine.arguments[1])
let module: Module
do {
    module = try Module(url: url)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let player = Player(module: module)
do {
    try player.start()
} catch {
    fputs("Audio engine failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

print("Playing:  \(module.title.isEmpty ? url.lastPathComponent : module.title)")
print("Format:   \(module.typeLong) (\(module.type)), \(module.numChannels)ch")
print(String(format: "Length:   %.1fs", module.durationSeconds))
print("Press Ctrl-C to stop.")

await player.waitUntilFinished()

/// Drives an `AVAudioEngine` source node from a libopenmpt `Module`.
///
/// The render block runs on a real-time audio thread; the module is
/// `@unchecked Sendable` so it can be captured safely. The `finished`
/// flag is the only other shared state and is guarded by a lock.
final class Player: @unchecked Sendable {
    private let module: Module
    private let engine = AVAudioEngine()
    private let sampleRate: Double = 48_000

    private let lock = NSLock()
    private var finished = false
    private var finishedContinuation: CheckedContinuation<Void, Never>?

    init(module: Module) {
        self.module = module
        module.setRepeatCount(0)
    }

    func start() throws {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!

        let module = self.module
        let rate = Int32(sampleRate)
        let onEndOfSong: @Sendable () -> Void = { [weak self] in
            self?.signalFinished()
        }

        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let leftRaw = abl[0].mData,
                  let rightRaw = abl[1].mData else {
                return noErr
            }
            let left = leftRaw.assumingMemoryBound(to: Float.self)
            let right = rightRaw.assumingMemoryBound(to: Float.self)
            let frames = Int(frameCount)

            let produced = module.renderStereo(
                sampleRate: rate,
                frameCount: frames,
                left: left,
                right: right
            )

            if produced < frames {
                for i in produced..<frames {
                    left[i] = 0
                    right[i] = 0
                }
                if produced == 0 {
                    onEndOfSong()
                }
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()
    }

    func waitUntilFinished() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if finished {
                lock.unlock()
                cont.resume()
            } else {
                finishedContinuation = cont
                lock.unlock()
            }
        }
        try? await Task.sleep(for: .milliseconds(200))
        engine.stop()
    }

    private func signalFinished() {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let cont = finishedContinuation
        finishedContinuation = nil
        lock.unlock()
        cont?.resume()
    }
}
