import AppKit
import ShiftlyKit
import SwiftUI

/// In-app Markdown editor for daily logs and quick notes: GitHub-style
/// Edit/Preview toggle, explicit Save, and a jump to VS Code. Presented as
/// its own window so it also works straight from the desktop widget.
@MainActor
enum LogEditorWindow {
    private static var windows: [NSWindow] = []

    /// Open an editor on an existing file.
    static func present(path: String, title: String, model: AppModel) {
        show(LogEditorView(model: model, mode: .file(path: path), windowTitle: title))
    }

    /// Open an editor that creates a quick note on save.
    static func presentNewNote(model: AppModel) {
        show(LogEditorView(model: model, mode: .newNote, windowTitle: L("New Note")))
    }

    private static func show(_ view: LogEditorView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = view.windowTitle
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
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

enum LogEditorMode: Equatable {
    case file(path: String)
    case newNote
}

struct LogEditorView: View {
    let model: AppModel
    let mode: LogEditorMode
    let windowTitle: String

    @State private var noteTitle = ""
    @State private var content = ""
    @State private var savedPath: String?
    @State private var showPreview = false
    @State private var dirty = false
    @State private var status = ""

    private var filePath: String? {
        if case .file(let path) = mode { return path }
        return savedPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if mode == .newNote {
                    TextField("Note title", text: $noteTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .disabled(savedPath != nil)
                } else {
                    Text(((filePath ?? "") as NSString).lastPathComponent)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Picker("", selection: $showPreview) {
                    Text("Edit").tag(false)
                    Text("Preview").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            Group {
                if showPreview {
                    ScrollView {
                        MarkdownPreview(content: content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                } else {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .onChange(of: content) { _ in dirty = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                Button("Open in VS Code") {
                    if let path = filePath {
                        model.openInVSCode(path: path)
                    }
                }
                .disabled(filePath == nil)
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Save") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(mode == .newNote && savedPath == nil
                              && noteTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { loadInitialContent() }
    }

    private func loadInitialContent() {
        guard case .file(let path) = mode else { return }
        content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        dirty = false
    }

    private func save() {
        if let path = filePath {
            status = model.saveEditorContent(content, at: path)
                ? L("Saved.") : L("Save failed.")
        } else {
            // First save of a new note creates the file, then edits go to it.
            if let path = model.createQuickNoteFile(title: noteTitle, body: content) {
                savedPath = path
                content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? content
                status = L("Saved.")
            } else {
                status = L("Save failed.")
            }
        }
        dirty = false
    }
}
