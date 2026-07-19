import AppKit
import AVFoundation
import ShiftlyKit
import SwiftUI

/// Meeting window: audio playback with the transcript (and translation)
/// below, the cue under the playhead highlighted and clickable to seek.
@MainActor
enum MeetingWindow {
    private static var windows: [NSWindow] = []

    static func present(meeting: MeetingStore.Meeting, model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(meeting.date) · \(meeting.time)"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: MeetingDetailView(meeting: meeting)
        )
        window.center()
        windows.append(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { notification in
            guard let closing = notification.object as? NSWindow else { return }
            Task { @MainActor in
                windows.removeAll { $0 === closing }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Playback state, polled 4×/s for the cue highlight.
@MainActor
final class MeetingPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(path: String) {
        player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        duration = player?.duration ?? 0
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, duration))
        currentTime = player.currentTime
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
    }

    func teardown() {
        player?.stop()
        timer?.invalidate()
        timer = nil
    }
}

struct MeetingDetailView: View {
    let meeting: MeetingStore.Meeting

    @StateObject private var player = MeetingPlayer()
    @State private var selectedLang: String = ""
    @State private var cuesByLang: [String: [SRT.Cue]] = [:]

    private var languages: [String] { cuesByLang.keys.sorted() }
    private var cues: [SRT.Cue] { cuesByLang[selectedLang] ?? [] }
    private var activeIndex: Int? { SRT.activeCueIndex(cues, at: player.currentTime) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if meeting.audioPath != nil {
                HStack(spacing: 12) {
                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    Text(timeText(player.currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 1)
                    )
                    Text(timeText(player.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No recording file in this folder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if languages.count > 1 {
                Picker("", selection: $selectedLang) {
                    ForEach(languages, id: \.self) { lang in
                        Text(lang.isEmpty ? "Transcript" : lang.uppercased()).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            if cues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No transcript yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Use Transcribe / Translate in the meeting list; the subtitles appear here once Scripto finishes.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(cues) { cue in
                                cueRow(cue, isActive: activeIndex == cue.id)
                                    .id(cue.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: activeIndex) { index in
                        if let index, player.isPlaying {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
        .padding(14)
        .frame(minWidth: 480, minHeight: 400)
        .onAppear { loadContent() }
        .onDisappear { player.teardown() }
    }

    @ViewBuilder
    private func cueRow(_ cue: SRT.Cue, isActive: Bool) -> some View {
        Button {
            player.seek(to: cue.start)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(timeText(cue.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 52, alignment: .leading)
                Text(cue.text)
                    .font(.subheadline)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func loadContent() {
        if let audio = meeting.audioPath {
            player.load(path: audio)
        }
        var parsed: [String: [SRT.Cue]] = [:]
        for (lang, path) in meeting.subtitles {
            if let data = FileManager.default.contents(atPath: path),
               let content = String(data: data, encoding: .utf8) {
                parsed[lang] = SRT.parse(content)
            }
        }
        cuesByLang = parsed
        selectedLang = languages.first ?? ""
    }
}
