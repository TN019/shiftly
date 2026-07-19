import ShiftlyKit
import SwiftUI

extension ContentView {
    @ViewBuilder
    var logSection: some View {
        if model.logDirExists {
            logTodayCard
            quickNotesCard
            logSearchCard
        } else {
            logSetupCard
        }
    }

    // MARK: Daily log

    private var logTodayCard: some View {
        card("Daily Log") {
            HStack(spacing: 10) {
                Text(model.activeLogDate)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                if model.activeLogDate != ContentView.ymdString(Date()) {
                    Text("no shift today — last workday")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button {
                    model.editDailyLog()
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                Button("Open in VS Code") {
                    Task { @MainActor in
                        if let path = await model.ensureLog(date: model.activeLogDate) {
                            model.openInVSCode(path: path)
                        }
                    }
                }
                .buttonStyle(.bordered)
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.logDir)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                TextField("Quick entry — appended with a timestamp", text: $logQuickText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitQuickCapture() }
                Button("Add") { submitQuickCapture() }
                    .buttonStyle(.bordered)
                    .disabled(logQuickText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let content = model.todayLogContent {
                ScrollView {
                    MarkdownPreview(content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 140, maxHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            } else {
                Text("No log for this day yet — Edit opens the editor, or add a quick entry above.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLogState()
        }
    }

    private func submitQuickCapture() {
        model.quickCapture(logQuickText)
        logQuickText = ""
    }

    // MARK: Quick notes

    private var quickNotesCard: some View {
        card("Quick Notes") {
            HStack(spacing: 10) {
                Text("Standalone notes — dd-mm-yy | title.md")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    model.newQuickNote()
                } label: {
                    Label("New Note", systemImage: "note.text.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    func noteRow(_ note: WorkLogStore.NoteRef) -> some View {
        HStack(spacing: 10) {
            Button {
                model.editFile(path: note.path, title: note.title)
            } label: {
                HStack(spacing: 10) {
                    Text(note.date)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(note.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in Shiftly")
            Button {
                model.openInVSCode(path: note.path)
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Open in VS Code")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: Search

    private var logSearchCard: some View {
        card("Logs") {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search logs and notes as you type", text: $logSearchQuery)
                    .textFieldStyle(.roundedBorder)
            }
            .task(id: logSearchQuery) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                model.searchLogs(query: logSearchQuery)
            }

            let searching = !logSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty
            let logDates = searching ? model.logSearchResults.map(\.date) : model.logDates
            let notes = searching ? model.noteSearchResults : model.quickNotes
            let snippets = Dictionary(
                model.logSearchResults.map { ($0.date, $0.snippet) },
                uniquingKeysWith: { a, _ in a }
            )

            Picker("", selection: $logsListShowsNotes) {
                Text(LF("Daily Logs (%lld)", logDates.count)).tag(false)
                Text(LF("Quick Notes (%lld)", notes.count)).tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            if logsListShowsNotes {
                if notes.isEmpty {
                    Text(searching ? "No matches." : "No notes yet.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(notes) { note in
                                noteRow(note)
                            }
                        }
                    }
                    .frame(maxHeight: 340)
                }
            } else {
                if logDates.isEmpty {
                    Text(searching ? "No matches." : "No logs yet.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(logDates, id: \.self) { date in
                                logRow(date: date, snippet: searching ? snippets[date] : nil)
                            }
                        }
                    }
                    .frame(maxHeight: 340)
                }
            }
        }
    }

    @ViewBuilder
    private func logRow(date: String, snippet: String?) -> some View {
        HStack(spacing: 10) {
            Button {
                let path = model.logStore.resolvedPath(for: date)
                model.editFile(path: path, title: LF("Daily Log — %@", date))
            } label: {
                HStack(spacing: 10) {
                    Text(date)
                        .font(.system(.subheadline, design: .monospaced))
                    if let snippet {
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in Shiftly")
            Button {
                model.openInVSCode(path: model.logStore.resolvedPath(for: date))
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Open in VS Code")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
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
