import ShiftlyKit
import SwiftUI

extension ContentView {
    @ViewBuilder
    var logSection: some View {
        if model.logDirExists {
            logTodayCard
        } else {
            logSetupCard
        }
    }

    private var logSetupCard: some View {
        card("Work Log") {
            Text("Daily Markdown logs live in a folder you own — one file per day (YYYY/YYYY-MM-DD.md) with the shift pre-filled, editable with any app.")
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

    private var logTodayCard: some View {
        card("Work Log") {
            HStack(spacing: 10) {
                Image(systemName: "text.book.closed")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's log")
                        .font(.subheadline.weight(.semibold))
                    Text(model.logStore.exists(date: AppModel.todayYMD())
                         ? "Exists — open to keep writing."
                         : "Not created yet — opening creates it with today's shift pre-filled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Open Today's Log") {
                    model.openTodayLog()
                }
                .buttonStyle(.borderedProminent)
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.logDir)
                }
                .buttonStyle(.bordered)
            }
            Text("Quick capture and in-app preview arrive with the next update.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
