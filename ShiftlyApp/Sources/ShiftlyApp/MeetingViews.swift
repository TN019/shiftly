import ShiftlyKit
import SwiftUI

extension ContentView {
    @ViewBuilder
    var meetingsPage: some View {
        meetingRecordCard
        meetingListCard
    }

    // MARK: Record

    private var meetingRecordCard: some View {
        card("") {
            HStack(spacing: 14) {
                Button {
                    model.isRecording ? model.stopRecording() : model.startRecording()
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.isRecording ? Color.red.opacity(0.18) : Color.red)
                            .frame(width: 44, height: 44)
                        Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(model.isRecording ? Color.red : Color.white)
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isRecording ? "Recording…" : "Record a meeting")
                        .font(.subheadline.weight(.semibold))
                    if model.isRecording {
                        Text(Self.elapsedText(model.recordingSeconds))
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    } else {
                        Text("Audio lands in a timestamped folder; Scripto adds the transcript next to it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    static func elapsedText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func chooseScriptoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose your Scripto checkout (the folder with pyproject.toml)."
        if panel.runModal() == .OK, let url = panel.url {
            model.adoptScriptoDir(url)
        }
    }

    // MARK: List

    private var meetingListCard: some View {
        card("Meetings") {
            if model.meetings.isEmpty {
                Text("No meetings yet — hit record.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.meetings) { meeting in
                            meetingRow(meeting)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
    }

    @ViewBuilder
    private func meetingRow(_ meeting: MeetingStore.Meeting) -> some View {
        let busy = model.scriptoBusy.contains(meeting.folder)
        HStack(spacing: 10) {
            Button {
                MeetingWindow.present(meeting: meeting, model: model)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(meeting.audioPath == nil ? Color.secondary : Color.accentColor)
                    Text("\(meeting.date) · \(meeting.time)")
                        .font(.system(.subheadline, design: .monospaced))
                    ForEach(meeting.subtitles.keys.sorted(), id: \.self) { lang in
                        Text(lang.isEmpty ? "srt" : lang.uppercased())
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(meeting.audioPath == nil && meeting.subtitles.isEmpty)

            if busy {
                ProgressView().controlSize(.small)
            } else {
                Button("Transcribe") { model.runScripto(meeting: meeting, translate: false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(meeting.audioPath == nil)
                Button("Translate") { model.runScripto(meeting: meeting, translate: true) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(meeting.audioPath == nil)
            }
            Button(role: .destructive) {
                model.deleteMeeting(meeting)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Move meeting to Trash")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
