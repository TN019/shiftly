import Foundation
import Testing
@testable import ShiftlyKit

@Suite struct MeetingStoreTests {
    @Test func folderNameRoundTrips() {
        #expect(MeetingStore.folderName(date: "2026-07-19", timeHHMM: "21:30") == "19-07-26 | 21-30")
        let parsed = MeetingStore.parseFolderName("19-07-26 | 21-30")
        #expect(parsed?.date == "2026-07-19")
        #expect(parsed?.time == "21:30")
        #expect(MeetingStore.parseFolderName("random folder") == nil)
        #expect(MeetingStore.parseFolderName("19-07-26 | junk") == nil)
        #expect(MeetingStore.audioFileName(date: "2026-07-19") == "19-07-26.mp4")
    }

    @Test func listsMeetingsWithAudioAndSubtitles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetings_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MeetingStore(rootDir: root)

        let audio = try store.newRecordingPath(date: "2026-07-19", timeHHMM: "21:30")
        #expect(audio.hasSuffix("/19-07-26 | 21-30/19-07-26.mp4"))
        FileManager.default.createFile(atPath: audio, contents: Data([0]))
        let folder = (audio as NSString).deletingLastPathComponent
        FileManager.default.createFile(atPath: folder + "/19-07-26.en.srt", contents: Data("x".utf8))
        FileManager.default.createFile(atPath: folder + "/19-07-26.zh.srt", contents: Data("y".utf8))
        // Recording scratch (hidden system-audio track) must never be
        // picked up as the meeting's audio or subtitles.
        FileManager.default.createFile(atPath: folder + "/.19-07-26.system.m4a", contents: Data([0]))
        FileManager.default.createFile(atPath: folder + "/.junk.srt", contents: Data("z".utf8))
        _ = try store.newRecordingPath(date: "2026-07-20", timeHHMM: "09:05")
        try FileManager.default.createDirectory(
            atPath: root + "/not a meeting", withIntermediateDirectories: true
        )

        let meetings = store.meetings()
        #expect(meetings.count == 2)
        #expect(meetings.first?.date == "2026-07-20", "newest first")
        let first = meetings.last!
        #expect(first.audioPath == audio)
        #expect(Set(first.subtitles.keys) == ["en", "zh"])
        #expect(meetings.first?.audioPath == nil, "recording not saved yet")
    }
}

@Suite struct SRTTests {
    let sample = """
    1
    00:00:01,000 --> 00:00:03,500
    Hello there.

    2
    00:00:04,000 --> 00:00:06,000
    Two lines
    of text.

    garbage block without timing

    3
    bad --> timing
    skipped
    """

    @Test func parsesCuesAndSkipsMalformedBlocks() {
        let cues = SRT.parse(sample)
        #expect(cues.count == 2)
        #expect(cues[0].start == 1.0)
        #expect(cues[0].end == 3.5)
        #expect(cues[0].text == "Hello there.")
        #expect(cues[1].text == "Two lines\nof text.")
    }

    @Test func activeCueTracksPlaybackTime() {
        let cues = SRT.parse(sample)
        #expect(SRT.activeCueIndex(cues, at: 0.0) == nil, "before the first cue")
        #expect(SRT.activeCueIndex(cues, at: 2.0) == 0)
        #expect(SRT.activeCueIndex(cues, at: 3.8) == 0, "gap keeps the last cue lit")
        #expect(SRT.activeCueIndex(cues, at: 5.0) == 1)
        #expect(SRT.activeCueIndex(cues, at: 60) == 1, "past the end stays on the last cue")
    }

    @Test func timestampVariants() {
        #expect(SRT.timestamp("01:02:03,500") == 3723.5)
        #expect(SRT.timestamp("00:00:10.250") == 10.25)
        #expect(SRT.timestamp("nonsense") == nil)
    }
}
