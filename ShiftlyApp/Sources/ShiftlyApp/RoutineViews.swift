import AppKit
import ShiftlyKit
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    // MARK: Today card

    @ViewBuilder
    var routineCard: some View {
        if !model.routine.isEmpty {
            card("") {
                HStack(spacing: 12) {
                    Image(systemName: "sunrise.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Work routine")
                            .font(.subheadline.weight(.semibold))
                        Text(LF("%lld of %lld steps enabled",
                                model.enabledRoutineSteps.count, model.routine.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        model.runRoutine()
                    } label: {
                        HStack(spacing: 6) {
                            if model.routineRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Start Work")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.routineRunning || model.enabledRoutineSteps.isEmpty)
                }
            }
        }
    }

    // MARK: Settings editor

    var routineSettingsCard: some View {
        card("Work Routine") {
            Text("One click opens your workday: apps, websites, folders, a shell command, a calendar sync, or a log entry. Unchecked steps stay configured but are skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(model.routine.enumerated()), id: \.element.id) { index, step in
                routineRow(index: index, step: step)
            }

            HStack(spacing: 8) {
                Text("Add:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("App…") { addAppStep() }
                Button("Website…") { appendStep(.init(kind: "url", value: "https://")) }
                Button("Ghostty @ folder…") { addGhosttyStep() }
                Button("Sync") { appendStep(.init(kind: "sync", value: "")) }
                Button("Log entry") { appendStep(.init(kind: "log", value: L("Started work"))) }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func routineRow(index: Int, step: RoutineStep) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { model.routine.indices.contains(index) ? model.routine[index].enabled : false },
                set: { on in mutateStep(index) { $0.enabled = on } }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Picker("", selection: Binding(
                get: { step.kind },
                set: { kind in mutateStep(index) { $0.kind = kind } }
            )) {
                Text("App").tag("app")
                Text("URL").tag("url")
                Text("Path").tag("path")
                Text("Command").tag("command")
                Text("Sync").tag("sync")
                Text("Log").tag("log")
            }
            .labelsHidden()
            .frame(width: 110)

            if step.kind == "sync" {
                Text("Run a calendar sync")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField(valuePlaceholder(step.kind), text: Binding(
                    get: { model.routine.indices.contains(index) ? model.routine[index].value : "" },
                    set: { value in mutateStep(index) { $0.value = value } }
                ))
            }

            if step.kind == "app" {
                TextField("--args (optional)", text: Binding(
                    get: { (model.routine.indices.contains(index) ? model.routine[index].args : nil)?.joined(separator: " ") ?? "" },
                    set: { text in
                        mutateStep(index) {
                            let parts = text.split(separator: " ").map(String.init)
                            $0.args = parts.isEmpty ? nil : parts
                        }
                    }
                ))
                .frame(width: 190)
            }

            Button(role: .destructive) {
                var steps = model.routine
                guard steps.indices.contains(index) else { return }
                steps.remove(at: index)
                model.updateRoutine(steps)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func valuePlaceholder(_ kind: String) -> String {
        switch kind {
        case "app": return "DingTalk"
        case "url": return "https://example.com"
        case "path": return "~/work"
        case "command": return "git -C ~/work pull"
        case "log": return L("Started work")
        default: return ""
        }
    }

    private func mutateStep(_ index: Int, _ change: (inout RoutineStep) -> Void) {
        var steps = model.routine
        guard steps.indices.contains(index) else { return }
        change(&steps[index])
        model.updateRoutine(steps)
    }

    private func appendStep(_ step: RoutineStep) {
        model.updateRoutine(model.routine + [step])
    }

    /// Pick an application from /Applications and add it as an app step.
    /// The step stores the app's display name (open -a resolves it).
    private func addAppStep() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose an app to open when you start work."
        if panel.runModal() == .OK, let url = panel.url {
            let name = url.deletingPathExtension().lastPathComponent
            appendStep(.init(kind: "app", value: name))
        }
    }

    private func addGhosttyStep() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose the working directory Ghostty should open in."
        if panel.runModal() == .OK, let url = panel.url {
            appendStep(.init(kind: "app", value: "Ghostty",
                             args: ["--working-directory=\(url.path)"]))
        }
    }
}
