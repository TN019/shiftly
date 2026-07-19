import Foundation

/// Meeting recordings on disk. One folder per meeting under the configured
/// root, named `dd-mm-yy | hh-mm` (start timestamp; ":" is reserved on
/// macOS, hence "hh-mm"). Inside: the recording `dd-mm-yy.mp4` plus the
/// subtitle files Scripto drops next to it (`dd-mm-yy.en.srt`,
/// `dd-mm-yy.zh.srt`, …). Shiftly only creates the folder and reads —
/// Scripto owns the SRT contents.
public struct MeetingStore {
    public let rootDir: String

    public init(rootDir: String) {
        self.rootDir = (rootDir as NSString).expandingTildeInPath
    }

    /// Default location when config.json has no meetings_dir.
    public static let defaultDir = "~/Documents/ShiftlyMeetings"

    public struct Meeting: Equatable, Identifiable {
        public var id: String { folder }
        public let folder: String
        /// YYYY-MM-DD (from the folder name).
        public let date: String
        /// HH:MM display time (from the folder name).
        public let time: String
        public let audioPath: String?
        /// Language code → SRT path, e.g. ["en": …, "zh": …].
        public let subtitles: [String: String]

        public init(folder: String, date: String, time: String,
                    audioPath: String?, subtitles: [String: String]) {
            self.folder = folder
            self.date = date
            self.time = time
            self.audioPath = audioPath
            self.subtitles = subtitles
        }
    }

    /// "2026-07-19", "21:30" → "19-07-26 | 21-30".
    public static func folderName(date: String, timeHHMM: String) -> String {
        let day = WorkLogStore.fileName(for: date).dropLast(3)
        return "\(day) | \(timeHHMM.replacingOccurrences(of: ":", with: "-"))"
    }

    /// "19-07-26 | 21-30" → ("2026-07-19", "21:30"); nil for other names.
    public static func parseFolderName(_ name: String) -> (date: String, time: String)? {
        guard let sep = name.range(of: " | "),
              let date = WorkLogStore.date(fromFileName: String(name[..<sep.lowerBound]) + ".md") else {
            return nil
        }
        let raw = String(name[sep.upperBound...])
        let parts = raw.split(separator: "-")
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && Int($0) != nil }) else {
            return nil
        }
        return (date, "\(parts[0]):\(parts[1])")
    }

    /// Recording file name for a meeting day.
    public static func audioFileName(date: String) -> String {
        String(WorkLogStore.fileName(for: date).dropLast(3)) + ".mp4"
    }

    /// Create the folder for a meeting starting now and return the audio
    /// path to record into.
    public func newRecordingPath(date: String, timeHHMM: String) throws -> String {
        let folder = "\(rootDir)/\(Self.folderName(date: date, timeHHMM: timeHHMM))"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return "\(folder)/\(Self.audioFileName(date: date))"
    }

    /// All meetings, newest first.
    public func meetings() -> [Meeting] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: rootDir) else { return [] }
        return names.compactMap { name -> Meeting? in
            guard let (date, time) = Self.parseFolderName(name) else { return nil }
            let folder = "\(rootDir)/\(name)"
            let files = (try? fm.contentsOfDirectory(atPath: folder)) ?? []
            let audio = files.first { $0.hasSuffix(".mp4") || $0.hasSuffix(".m4a") }
            var subtitles: [String: String] = [:]
            for file in files where file.hasSuffix(".srt") {
                // "<stem>.<lang>.srt" → lang; a bare "<stem>.srt" is the
                // untagged transcript.
                let stem = file.dropLast(4)
                let lang = stem.contains(".") ? String(stem.split(separator: ".").last!) : ""
                subtitles[lang] = "\(folder)/\(file)"
            }
            return Meeting(
                folder: folder,
                date: date,
                time: time,
                audioPath: audio.map { "\(folder)/\($0)" },
                subtitles: subtitles
            )
        }
        .sorted { ($0.date, $0.time) > ($1.date, $1.time) }
    }
}

/// Minimal SRT parsing for in-app display and playback highlighting.
public enum SRT {
    public struct Cue: Equatable, Identifiable {
        public let id: Int
        public let start: TimeInterval
        public let end: TimeInterval
        public let text: String

        public init(id: Int, start: TimeInterval, end: TimeInterval, text: String) {
            self.id = id
            self.start = start
            self.end = end
            self.text = text
        }
    }

    /// Parses SRT content; malformed blocks are skipped, never fatal.
    public static func parse(_ content: String) -> [Cue] {
        let blocks = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        var cues: [Cue] = []
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true)
            guard let timing = lines.first(where: { $0.contains("-->") }) else { continue }
            let parts = timing.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = timestamp(parts[0]),
                  let end = timestamp(parts[1]) else { continue }
            let textLines = lines
                .drop(while: { !$0.contains("-->") })
                .dropFirst()
                .map(String.init)
            guard !textLines.isEmpty else { continue }
            cues.append(Cue(
                id: cues.count,
                start: start,
                end: end,
                text: textLines.joined(separator: "\n")
            ))
        }
        return cues
    }

    /// "00:01:02,500" (or "00:01:02.500") → seconds.
    static func timestamp(_ raw: String) -> TimeInterval? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    /// Index of the cue covering `time` (last started cue), nil before the
    /// first cue.
    public static func activeCueIndex(_ cues: [Cue], at time: TimeInterval) -> Int? {
        var active: Int?
        for (index, cue) in cues.enumerated() {
            if cue.start <= time {
                active = index
            } else {
                break
            }
        }
        if let active, cues[active].end < time, active + 1 < cues.count {
            return active // between cues: keep the last one lit
        }
        return active
    }
}

extension Config {
    /// Meeting recordings folder (nil = MeetingStore.defaultDir).
    public var meetingsRoot: String {
        ((meetings_dir ?? MeetingStore.defaultDir) as NSString).expandingTildeInPath
    }
}
