// BudsBar — the audio stream that reaches the earbuds
// SPDX-License-Identifier: MIT
//
// The earbuds never report their codec: the negotiation happens between
// macOS and the Bluetooth controller, and the result stays inside the
// system. The system does write the outcome into its log, though, and that
// is where the numbers come from.
//
// The daemon only writes the line when something asks it for the controller
// information. `system_profiler` does exactly that, and it is cheap — it
// answers in a tenth of a second. The line is then read back from the log.
//
// The sample rate comes from CoreAudio instead: it describes the stream the
// system actually plays, while the log describes the codec the two sides
// agreed on.

import Foundation

/// What the system currently streams to the earbuds.
public struct AudioCodecInfo: Equatable, Sendable {
    /// The codec the Bluetooth stack negotiated, for example `AAC-LC`.
    public var codec: String?
    /// The bitrate of the stream, in kilobits per second.
    public var bitrateKbps: Int?
    /// The sample rate of the output stream, in hertz.
    public var sampleRate: Double?
    /// The name of the audio device the stream goes to.
    public var deviceName: String?
    /// Whether the stream is a Bluetooth audio profile.
    public var isBluetooth: Bool

    public init(
        codec: String? = nil,
        bitrateKbps: Int? = nil,
        sampleRate: Double? = nil,
        deviceName: String? = nil,
        isBluetooth: Bool = false
    ) {
        self.codec = codec
        self.bitrateKbps = bitrateKbps
        self.sampleRate = sampleRate
        self.deviceName = deviceName
        self.isBluetooth = isBluetooth
    }

    /// Whether anything at all is known about the stream.
    public var isEmpty: Bool {
        codec == nil && bitrateKbps == nil && sampleRate == nil && !isBluetooth
    }

    /// A short description of the stream, for the panel.
    ///
    /// Falls back to the Bluetooth profile on its own when the codec itself
    /// could not be read, so the line always says something true.
    public var summary: String? {
        var parts: [String] = []
        if let codec { parts.append(codec) }
        if let bitrateKbps { parts.append("\(bitrateKbps) kbps") }
        if let sampleRate { parts.append(AudioCodecInfo.rateLabel(sampleRate)) }
        if parts.isEmpty {
            return isBluetooth ? "Bluetooth A2DP" : nil
        }
        return parts.joined(separator: " · ")
    }

    /// Formats a sample rate as kilohertz.
    public static func rateLabel(_ hertz: Double) -> String {
        let kilohertz = hertz / 1000
        if kilohertz == kilohertz.rounded() {
            return "\(Int(kilohertz)) kHz"
        }
        return String(format: "%.1f kHz", kilohertz)
    }
}

/// Reads the codec the system negotiated with the earbuds.
public enum CodecDetector {

    /// The predicate that selects the daemon's controller information.
    ///
    /// The daemon writes the line for every device it knows, so the line of
    /// the earbuds is picked out by its device name afterwards.
    private static let predicate = "eventMessage CONTAINS \"BtRt\""

    /// Reads the current codec, bitrate and sample rate of the earbuds.
    ///
    /// - Parameter deviceName: the name of the audio device, as the system
    ///   knows it. The display name of the model is a good guess for it.
    public static func detect(deviceName: String?) async -> AudioCodecInfo {
        await Task.detached(priority: .utility) {
            let audio = OutputVolume.outputInfo(named: deviceName)

            // Asking the system for the Bluetooth devices makes the daemon
            // write the controller information into the log.
            Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType"])

            // The daemon writes the line a moment after the question.
            var info = AudioCodecInfo()
            for attempt in 0..<2 {
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 120 : 400))
                let log = Shell.run("/usr/bin/log", [
                    "show", "--last", "20s", "--predicate", predicate, "--style", "compact"
                ])
                info = CodecDetector.parse(log, deviceName: audio.name ?? deviceName)
                if !info.isEmpty { break }
            }

            info.sampleRate = audio.sampleRate
            info.deviceName = info.deviceName ?? audio.name
            info.isBluetooth = audio.isBluetooth
            return info
        }.value
    }

    /// Parses the controller information out of a log.
    ///
    /// The daemon writes one line per device, so the newest line that
    /// belongs to the earbuds is the one that describes the current stream.
    ///
    /// - Parameters:
    ///   - log: the text of the log.
    ///   - deviceName: the name of the earbuds in the log. Lines of other
    ///     devices are ignored.
    public static func parse(_ log: String, deviceName: String?) -> AudioCodecInfo {
        guard let wanted = deviceName?.lowercased(), !wanted.isEmpty else {
            return AudioCodecInfo()
        }

        var newest: (stamp: String, info: AudioCodecInfo)?
        for line in log.split(separator: "\n") {
            let text = String(line)
            guard let info = parseLine(text) else { continue }
            guard info.deviceName?.lowercased() == wanted else { continue }
            let stamp = stamp(of: text)
            if newest == nil || stamp >= newest!.stamp {
                newest = (stamp, info)
            }
        }
        return newest?.info ?? AudioCodecInfo()
    }

    /// Reads the codec out of a single log line.
    private static func parseLine(_ line: String) -> AudioCodecInfo? {
        guard let codec = match("Codc ([^,]+)", in: line) else { return nil }
        var info = AudioCodecInfo(codec: codec)
        if let bitrate = match("BtRt ([0-9]+) Kbps", in: line) {
            info.bitrateKbps = Int(bitrate)
        }
        if let device = match("DvNm '([^']*)'", in: line) {
            info.deviceName = device
        }
        return info
    }

    /// The first capture of a pattern in a line.
    private static func match(_ pattern: String, in line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let found = regex.firstMatch(in: line, range: range), found.numberOfRanges > 1,
              let capture = Range(found.range(at: 1), in: line)
        else { return nil }
        return String(line[capture]).trimmingCharacters(in: .whitespaces)
    }

    /// The timestamp that starts a log line.
    ///
    /// The stamps have a fixed width, so they can be compared as text.
    private static func stamp(of line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return "" }
        return "\(parts[0]) \(parts[1])"
    }
}

/// Runs a command and returns what it printed.
fileprivate enum Shell {
    /// Runs an executable and returns its standard output.
    ///
    /// The error output is thrown away: a missing tool or a denied query
    /// should not stop the panel, it should only leave it without the
    /// numbers it wanted.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
