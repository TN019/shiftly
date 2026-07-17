import ShiftlyKit
import SwiftUI

/// Sheet: rule timeline (history read-only, future editable) + shift types.
struct ScheduleManagerSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    // New-rule form
    @State private var newRuleDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var newRuleDays: Set<String> = []
    @State private var newRuleType: String? = nil

    // Shift-type editor
    @State private var editedTypes: [ShiftType] = []
    @State private var typesDirty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Rules & Shift Types")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    timelineSection
                    Divider()
                    newRuleSection
                    Divider()
                    shiftTypesSection
                }
                .padding(.bottom, 12)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 540)
        .onAppear {
            editedTypes = model.shiftTypes
            newRuleDays = model.selectedDays
            newRuleType = model.selectedShiftType
        }
    }

    // MARK: Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rule timeline")
                .font(.headline)
            Text("The rule with the latest effective date on or before a day decides that day's schedule. Past rules are history — they keep old work records correct and cannot be edited.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.rules.isEmpty {
                Text("No rules yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            ForEach(model.rules.sorted { $0.effective_from > $1.effective_from }, id: \.effective_from) { rule in
                ruleRow(rule)
            }
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
        let today = AppModel.todayYMD()
        let isFuture = rule.effective_from > today
        let isActive = !isFuture && rule.effective_from == (
            model.rules.filter { $0.effective_from <= today }.map(\.effective_from).max() ?? ""
        )
        return HStack(spacing: 10) {
            Text(rule.effective_from)
                .font(.system(.subheadline, design: .monospaced))
            Text(rule.workdays.joined(separator: " "))
                .font(.subheadline.weight(.medium))
            if let typeID = rule.shift_type,
               let type = model.shiftTypes.first(where: { $0.id == typeID }) {
                Text("\(type.label) \(type.start)–\(type.end)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.purple.opacity(0.15)))
            } else if let typeID = rule.shift_type {
                Text("\(typeID) (missing type)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("default times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isActive {
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            } else if isFuture {
                Text("Scheduled")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                Button(role: .destructive) {
                    model.deleteRule(effectiveFrom: rule.effective_from)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this scheduled change")
            } else {
                Text("History")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: New rule

    private var newRuleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule a change")
                .font(.headline)
            HStack(spacing: 10) {
                DatePicker("", selection: $newRuleDate, in: Date()..., displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                ForEach(model.dayOrder, id: \.self) { code in
                    let on = newRuleDays.contains(code)
                    Button(model.dayLabels[code] ?? code) {
                        if on { newRuleDays.remove(code) } else { newRuleDays.insert(code) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.16), in: Capsule())
                    .foregroundStyle(on ? Color.white : Color.primary)
                }
            }
            HStack(spacing: 10) {
                Picker("Shift type", selection: $newRuleType) {
                    Text("Default times").tag(String?.none)
                    ForEach(model.shiftTypes) { type in
                        Text("\(type.label) (\(type.start)–\(type.end))").tag(String?.some(type.id))
                    }
                }
                .frame(maxWidth: 280)
                Button("Add rule") {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    model.upsertRule(
                        effectiveFrom: df.string(from: newRuleDate),
                        workdays: model.dayOrder.filter { newRuleDays.contains($0) },
                        shiftType: newRuleType
                    )
                }
                .buttonStyle(.bordered)
                .disabled(newRuleDays.isEmpty)
            }
        }
    }

    // MARK: Shift types

    private var shiftTypesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shift types")
                .font(.headline)
            Text("Each type has its own times; end at or before start rolls into the next day (overnight). Rules pick a type, or use the default times.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach($editedTypes) { $type in
                HStack(spacing: 8) {
                    TextField("id", text: $type.id)
                        .frame(width: 80)
                    TextField("Label", text: $type.label)
                        .frame(width: 110)
                    TextField("10:00", text: $type.start)
                        .frame(width: 64)
                    Text("–").foregroundStyle(.secondary)
                    TextField("18:30", text: $type.end)
                        .frame(width: 64)
                    let uses = model.ruleCount(usingShiftType: type.id)
                    Text(uses == 1 ? "1 rule" : "\(uses) rules")
                        .font(.caption)
                        .foregroundStyle(uses > 0 ? Color.orange : Color.secondary)
                        .help(uses > 0 ? "Changing or removing this type affects \(uses) rule(s)" : "Unused")
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        editedTypes.removeAll { $0.id == type.id }
                        typesDirty = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .onChange(of: type) { _ in typesDirty = true }
            }
            HStack(spacing: 10) {
                Button {
                    var n = 1
                    while editedTypes.contains(where: { $0.id == "type\(n)" }) { n += 1 }
                    editedTypes.append(ShiftType(id: "type\(n)", label: "New Type", start: "09:00", end: "17:00"))
                    typesDirty = true
                } label: {
                    Label("Add type", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Button("Save types") {
                    model.saveShiftTypes(cleanedTypes())
                    typesDirty = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!typesDirty || !typesValid())
                if !typesValid() {
                    Text("Ids must be unique and times HH:MM.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func cleanedTypes() -> [ShiftType] {
        editedTypes.map {
            ShiftType(
                id: $0.id.trimmingCharacters(in: .whitespaces),
                label: $0.label.trimmingCharacters(in: .whitespaces),
                start: $0.start.trimmingCharacters(in: .whitespaces),
                end: $0.end.trimmingCharacters(in: .whitespaces)
            )
        }
    }

    private func typesValid() -> Bool {
        let types = cleanedTypes()
        let ids = types.map(\.id)
        guard Set(ids).count == ids.count else { return false }
        let hhmm = try! NSRegularExpression(pattern: "^\\d{1,2}:\\d{2}$")
        return types.allSatisfy { type in
            !type.id.isEmpty && !type.label.isEmpty
                && hhmm.firstMatch(in: type.start, range: NSRange(type.start.startIndex..., in: type.start)) != nil
                && hhmm.firstMatch(in: type.end, range: NSRange(type.end.startIndex..., in: type.end)) != nil
        }
    }
}
