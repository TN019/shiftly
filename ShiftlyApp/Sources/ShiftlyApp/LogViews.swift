import ShiftlyKit
import SwiftUI

extension ContentView {
    @ViewBuilder
    var logSection: some View {
        if model.logDirExists {
            logQuickCaptureCard
            logTodayCard
            quickNotesCard
            logSearchCard
        } else {
            logSetupCard
        }
    }

    // MARK: Quick notes

    private var quickNotesCard: some View {
        card("Quick Notes") {
            HStack(spacing: 10) {
                Image(systemName: "note.text.badge.plus")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                TextField("Note title — creates dd-mm-yy | title.md and opens it", text: $quickNoteTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitQuickNote() }
                Button("Create") { submitQuickNote() }
                    .buttonStyle(.borderedProminent)
                    .disabled(quickNoteTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !model.quickNotes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.quickNotes) { note in
                            Button {
                                NSWorkspace.shared.open(URL(fileURLWithPath: note.path))
                            } label: {
                                HStack(spacing: 10) {
                                    Text(note.date)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(note.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.forward.square")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            } else {
                Text("No notes yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func submitQuickNote() {
        model.createQuickNote(title: quickNoteTitle)
        quickNoteTitle = ""
    }

    // MARK: Search

    private var logSearchCard: some View {
        card("Search Logs") {
            HStack(spacing: 10) {
                TextField("Keyword — matches frontmatter and body", text: $logSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runLogSearch() }
                Toggle("Date range", isOn: $logSearchUseRange)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                if logSearchUseRange {
                    styledDatePicker($logSearchFrom)
                    styledDatePicker($logSearchTo)
                }
                Button("Search") { runLogSearch() }
                    .buttonStyle(.bordered)
                    .disabled(logSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !model.logSearchResults.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.logSearchResults) { hit in
                            Button {
                                model.openLog(date: hit.date)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(hit.date)
                                        .font(.system(.subheadline, design: .monospaced))
                                    Text(hit.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.forward.square")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            } else if logSearchRan {
                Text("No matches.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func runLogSearch() {
        let query = logSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        logSearchRan = true
        model.searchLogs(
            query: query,
            from: logSearchUseRange ? ContentView.ymdString(logSearchFrom) : nil,
            to: logSearchUseRange ? ContentView.ymdString(logSearchTo) : nil
        )
    }

    private var logSetupCard: some View {
        card("Work Log") {
            Text("Daily Markdown logs live in a folder you own — one file per shift day (dd-mm-yy.md) with the shift pre-filled, plus standalone quick notes (dd-mm-yy | title.md), editable with any app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(model.logDir)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button("Create This Folder") {
                    model.createLogDir()
                }
                .buttonStyle(.borderedProminent)
                Button("Choose Another…") {
                    chooseLogFolder()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Quick capture

    private var logQuickCaptureCard: some View {
        card("") {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                TextField("Daily log — appended with a timestamp", text: $logQuickText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitQuickCapture() }
                Button("Add") { submitQuickCapture() }
                    .buttonStyle(.borderedProminent)
                    .disabled(logQuickText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if model.activeLogDate != ContentView.ymdString(Date()) {
                Text(LF("No shift today — entries go to %@, the last workday.", model.activeLogDate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func submitQuickCapture() {
        model.quickCapture(logQuickText)
        logQuickText = ""
    }

    // MARK: Today's log

    private var logTodayCard: some View {
        card("Daily Log") {
            Text(model.activeLogDate)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Picker("", selection: $logShowRaw) {
                    Text("Preview").tag(false)
                    Text("Raw").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 170)
                Spacer(minLength: 0)
                Button("Open in Editor") {
                    model.openTodayLog()
                }
                .buttonStyle(.bordered)
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.logDir)
                }
                .buttonStyle(.bordered)
            }

            if let content = model.todayLogContent {
                ScrollView {
                    Group {
                        if logShowRaw {
                            Text(content)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        } else {
                            MarkdownPreview(content: content)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(minHeight: 160, maxHeight: 340)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            } else {
                Text("No log for today yet — add a quick note above or open it in an editor to start.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Text("Edits made in other apps show up when Shiftly comes back to the front.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLogState()
        }
    }

    func chooseLogFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder for your work logs."
        if panel.runModal() == .OK, let url = panel.url {
            model.adoptLogDir(url)
        }
    }
}

/// Lightweight line-based Markdown preview: headers, bullets, frontmatter
/// shown dimmed, inline styles via AttributedString. Full fidelity belongs
/// to the user's own editor — this is a glanceable in-app rendering.
struct MarkdownPreview: View {
    let content: String

    var body: some View {
        let (frontmatter, body) = Self.split(content)
        VStack(alignment: .leading, spacing: 5) {
            if !frontmatter.isEmpty {
                Text(frontmatter)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 4)
            }
            ForEach(Array(body.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("### ") {
            Text(inline(String(line.dropFirst(4)))).font(.subheadline.weight(.semibold))
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3)))).font(.headline)
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2)))).font(.title3.weight(.bold))
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(String(line.dropFirst(2))))
            }
        } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Spacer().frame(height: 4)
        } else {
            Text(inline(line))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    /// Separate a leading YAML frontmatter block from the body lines.
    static func split(_ content: String) -> (frontmatter: String, body: [String]) {
        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---",
              let close = lines.dropFirst().firstIndex(of: "---") else {
            return ("", lines)
        }
        let front = lines[0...close].joined(separator: "\n")
        return (front, Array(lines[(close + 1)...]))
    }
}
