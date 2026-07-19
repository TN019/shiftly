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
            contentRect: NSRect(x: 0, y: 0, width: 176, height: 176),
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
        // The autosaved frame may carry an older widget size; the card is
        // fixed-size, so always normalize.
        panel.setContentSize(NSSize(width: 176, height: 176))
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

/// The widget card itself: date, next shift, and the one-click start-work
/// button. Sized and styled like a native small desktop widget (square,
/// large continuous corners, material background, no border).
struct DesktopWidgetView: View {
    @ObservedObject var model: AppModel
    @State private var showNoteInput = false
    @State private var noteTitle = ""

    private var canStart: Bool {
        !model.routineRunning && !model.enabledRoutineSteps.isEmpty
    }

    private func submitNote() {
        let title = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        model.createQuickNote(title: title)
        noteTitle = ""
        showNoteInput = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .textCase(.uppercase)
                Text(Date().formatted(.dateTime.day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "calendar.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            if let shift = model.nextShift {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next shift")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(shift.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if shift.start > Date() {
                        Text("\(shift.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(shift.start.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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
                    .lineLimit(3)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button {
                    model.runRoutine()
                } label: {
                    HStack(spacing: 5) {
                        if model.routineRunning {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text("Start Work")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(canStart ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(
                        canStart ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
                .help(model.enabledRoutineSteps.isEmpty
                      ? Text("Configure the routine in Shiftly → Settings")
                      : Text(""))

                Button {
                    model.syncNow()
                } label: {
                    Group {
                        if model.isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: Circle())
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .help(Text("Sync Now"))

                Button {
                    showNoteInput = true
                } label: {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Text("Quick note"))
                .popover(isPresented: $showNoteInput, arrowEdge: .bottom) {
                    HStack(spacing: 8) {
                        TextField("Note title", text: $noteTitle)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onSubmit { submitNote() }
                        Button("Create") { submitNote() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(noteTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(10)
                }
            }
        }
        .padding(16)
        .frame(width: 176, height: 176)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
