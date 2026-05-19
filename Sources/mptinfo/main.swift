import OpenMPTKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: mptinfo <file> [file...]\n", stderr)
    exit(1)
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(filePath: path)
    let mod: Module
    do {
        mod = try Module(url: url)
    } catch {
        fputs("Error loading \(path): \(error.localizedDescription)\n", stderr)
        continue
    }

    print("File:       \(url.lastPathComponent)")
    print("Title:      \(mod.title.isEmpty ? "(none)" : mod.title)")
    if !mod.artist.isEmpty { print("Artist:     \(mod.artist)") }
    if !mod.date.isEmpty   { print("Date:       \(mod.date)") }
    print("Format:     \(mod.typeLong) (\(mod.type))")
    if !mod.tracker.isEmpty { print("Tracker:    \(mod.tracker)") }
    print("Channels:   \(mod.numChannels)")
    print("Orders:     \(mod.numOrders)")
    print("Patterns:   \(mod.numPatterns)")

    if mod.numInstruments > 0 {
        print("Instruments: \(mod.numInstruments)")
        for (i, name) in mod.instrumentNames.enumerated() where !name.isEmpty {
            print("  \(String(format: "%02d", i + 1)): \(name)")
        }
    }

    if mod.numSamples > 0 {
        print("Samples:    \(mod.numSamples)")
        for (i, name) in mod.sampleNames.enumerated() where !name.isEmpty {
            print("  \(String(format: "%02d", i + 1)): \(name)")
        }
    }

    if !mod.message.isEmpty {
        print("Message:")
        for line in mod.message.split(separator: "\n", omittingEmptySubsequences: false) {
            print("  \(line)")
        }
    }

    print("")
}
