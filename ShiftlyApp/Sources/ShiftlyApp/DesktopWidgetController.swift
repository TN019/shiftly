import AppKit
import ShiftlyKit
import SwiftUI

/// Desktop widget: a borderless non-activating panel pinned just above the
/// desktop icons (below all normal windows), like a system widget. Draggable
/// anywhere, position remembered. Content is SwiftUI (DesktopWidgetView).
@MainActor
final class DesktopWidgetController {
    private unowned let model: AppModel
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 264, height: 168),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DesktopWidgetView(model: model))

        panel.setFrameAutosaveName("shiftly.desktopWidget")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            // First run: top-right corner with a margin.
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.maxX - panel.frame.width - 24,
                y: frame.maxY - panel.frame.height - 24
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func remove() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The widget card itself: date, next shift, and the one-click
/// start-work button.
struct DesktopWidgetView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Shiftly")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.defaultDigits).day()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let shift = model.nextShift {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next shift")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(shift.start.formatted(date: .abbreviated, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    if shift.start > Date() {
                        Text(shift.start.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("in progress")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("No upcoming shift in the next 45 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button {
                model.runRoutine()
            } label: {
                HStack(spacing: 6) {
                    if model.routineRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text("Start Work")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.routineRunning || model.enabledRoutineSteps.isEmpty)
            .help(model.enabledRoutineSteps.isEmpty
                  ? Text("Configure the routine in Shiftly → Settings")
                  : Text(""))
        }
        .padding(14)
        .frame(width: 264, height: 168)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
