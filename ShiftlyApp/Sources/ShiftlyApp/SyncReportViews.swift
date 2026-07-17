import ShiftlyKit
import SwiftUI

extension ContentView {
    var syncReportSection: some View {
        card("Sync Report") {
            if let report = model.lastReport {
                HStack(spacing: 8) {
                    Circle()
                        .fill(report.status == "success" ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(report.status == "success" ? "Last sync succeeded" : "Last sync failed")
                        .font(.subheadline.weight(.medium))
                    Text(report.at)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(reportCounts(report))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let error = report.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if !report.ignored_foreign.isEmpty {
                    Text("Skipped (not managed by Shiftly): \(report.ignored_foreign.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No sync yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            if !model.readbackLog.isEmpty {
                Divider()
                Text("Changes read back from Calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.readbackLog) { record in
                            readbackRow(record)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    @ViewBuilder
    private func readbackRow(_ record: ReadbackRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: readbackIcon(record.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(readbackDescription(record))
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .strikethrough(record.undone)
                .foregroundStyle(record.undone ? Color.secondary : Color.primary)
            Spacer(minLength: 0)
            if record.undone {
                Text("Undone")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else {
                Button("Undo") {
                    model.undoReadback(record)
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func reportCounts(_ report: SyncReportFile) -> String {
        "+\(report.created) ~\(report.updated) -\(report.deleted) · \(report.readback_count) read back"
    }

    private func readbackIcon(_ kind: ReadbackRecord.Kind) -> String {
        switch kind {
        case .moved: return "arrow.right"
        case .retimed: return "clock"
        case .deleted: return "minus.circle"
        case .newManual: return "plus.circle"
        }
    }

    private func readbackDescription(_ record: ReadbackRecord) -> String {
        switch record.kind {
        case .moved:
            return "\(record.date) moved to \(record.to_date ?? "?") (swap)"
        case .retimed:
            return "\(record.date) retimed to \(record.start ?? "?")–\(record.end ?? "?")"
        case .deleted:
            return "\(record.date) removed in Calendar (day off)"
        case .newManual:
            return "\(record.date) added in Calendar \(record.start ?? "?")–\(record.end ?? "?") (manual shift)"
        }
    }
}
