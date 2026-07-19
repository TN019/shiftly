import SwiftUI
import WidgetKit

// Native WidgetKit widgets (small square + medium rectangle). Built by
// scripts/build_app.sh with plain swiftc into PlugIns/ShiftlyWidgets.appex —
// no Xcode involved, ad-hoc signed with the sandbox entitlement WidgetKit
// requires. Display-only: the app writes a snapshot JSON into the shared
// group container on every data refresh and pokes WidgetCenter; tapping a
// widget opens Shiftly.

private let groupID = "group.com.shiftly.app"

struct UpcomingLine: Decodable {
    let day: String
    let time: String
}

struct Snapshot: Decodable {
    let label: String
    let time: String
    let sub: String
    let upcoming: [UpcomingLine]
}

struct ShiftEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}

private let placeholderSnapshot = Snapshot(
    label: "Next shift", time: "10:00", sub: "Tue, 21 Jul",
    upcoming: [
        UpcomingLine(day: "Tue 21 Jul", time: "10:00 – 18:30"),
        UpcomingLine(day: "Fri 24 Jul", time: "10:00 – 18:30"),
        UpcomingLine(day: "Sat 25 Jul", time: "10:00 – 18:30"),
    ]
)

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ShiftEntry {
        ShiftEntry(date: .now, snapshot: placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
        completion(ShiftEntry(date: .now, snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
        completion(Timeline(
            entries: [ShiftEntry(date: .now, snapshot: load())],
            policy: .after(Date().addingTimeInterval(1800))
        ))
    }

    private func load() -> Snapshot {
        let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("widget.json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(label: "Next shift", time: "—",
                            sub: "Open Shiftly once", upcoming: [])
        }
        return snapshot
    }
}

struct NextShiftBlock: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .textCase(.uppercase)
                Text(Date().formatted(.dateTime.day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text(snapshot.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapshot.time)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(snapshot.sub)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ShiftlyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ShiftEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                HStack(spacing: 14) {
                    NextShiftBlock(snapshot: entry.snapshot)
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Upcoming")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if entry.snapshot.upcoming.isEmpty {
                            Text("No shifts planned")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(entry.snapshot.upcoming.prefix(3), id: \.day) { line in
                                HStack(spacing: 8) {
                                    Text(line.day)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 76, alignment: .leading)
                                    Text(line.time)
                                        .font(.caption.weight(.medium))
                                        .monospacedDigit()
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            default:
                NextShiftBlock(snapshot: entry.snapshot)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct NextShiftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShiftlyNextShift", provider: Provider()) { entry in
            ShiftlyWidgetView(entry: entry)
        }
        .configurationDisplayName("Shiftly")
        .description("Your next shifts at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ShiftlyWidgets: WidgetBundle {
    var body: some Widget {
        NextShiftWidget()
    }
}
