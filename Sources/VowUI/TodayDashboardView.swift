import VowCore

#if canImport(SwiftUI)
import SwiftUI

/// Founder "Today" single-screen ritual.
///
/// This is deliberately host-agnostic: the host app wires real persistence
/// and action handlers via the callbacks.
public struct TodayDashboardView: View {
    // MARK: - Inputs

    public struct FocusStatus: Equatable {
        public var isInFocusSession: Bool
        public var secondsInSession: TimeInterval
        public var targetSeconds: TimeInterval
        public var completed: Bool

        public init(
            isInFocusSession: Bool = false,
            secondsInSession: TimeInterval = 0,
            targetSeconds: TimeInterval = 0,
            completed: Bool = false
        ) {
            self.isInFocusSession = isInFocusSession
            self.secondsInSession = secondsInSession
            self.targetSeconds = targetSeconds
            self.completed = completed
        }

        public var progress: Double {
            guard targetSeconds > 0 else { return 0 }
            return min(1.0, max(0.0, secondsInSession / targetSeconds))
        }
    }

    public struct LifeCheckIn: Equatable {
        public var prompt: String

        public init(prompt: String = "What did you do today that you’re proud of—what will you do next?") {
            self.prompt = prompt
        }
    }

    public struct AtomicHabitRow: Identifiable, Equatable {
        public let id: UUID
        public let instance: AtomicHabitInstanceRecord
        public let definition: AtomicHabitDefinitionRecord
        public let microCommitment: AtomicHabitEngine.MicroCommitment?

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.instance == rhs.instance && lhs.definition.id == rhs.definition.id
        }
    }

    @Binding private var journalText: String

    private let focusStatus: FocusStatus
    private let lifeCheckIn: LifeCheckIn

    private let habitRows: [AtomicHabitRow]
    private let evidencePolicy: EvidencePolicy
    private let completionHint: String

    // MARK: - Callbacks

    private let onToggleFocus: () -> Void
    private let onQuickCompleteHabit: (AtomicHabitInstanceRecord) -> Void
    private let onSubmitLifeCheckIn: (String) -> Void
    private let onNextFrictionlessAction: () -> Void

    // MARK: - Init

    public init(
        focusStatus: FocusStatus,
        lifeCheckIn: LifeCheckIn = .init(),
        habitInstances: [AtomicHabitInstanceRecord],
        habitDefinitions: [AtomicHabitDefinitionRecord],
        evidencePolicy: EvidencePolicy = EvidencePolicy(),
        completionHint: String = "Tiny wins count—keep it frictionless.",
        journalText: Binding<String>,
        onToggleFocus: @escaping () -> Void,
        onQuickCompleteHabit: @escaping (AtomicHabitInstanceRecord) -> Void,
        onSubmitLifeCheckIn: @escaping (String) -> Void,
        onNextFrictionlessAction: @escaping () -> Void
    ) {
        self.focusStatus = focusStatus
        self.lifeCheckIn = lifeCheckIn
        self.evidencePolicy = evidencePolicy
        self.completionHint = completionHint
        self.onToggleFocus = onToggleFocus
        self.onQuickCompleteHabit = onQuickCompleteHabit
        self.onSubmitLifeCheckIn = onSubmitLifeCheckIn
        self.onNextFrictionlessAction = onNextFrictionlessAction
        self._journalText = journalText

        let defByID = Dictionary(uniqueKeysWithValues: habitDefinitions.map { ($0.id, $0) })
        let engine = AtomicHabitEngine()
        self.habitRows = habitInstances.compactMap { inst in
            guard let def = defByID[inst.habitDefinitionID] else { return nil }
            let micro = engine.microCommitment(habitKind: def.habitKind, name: def.name, evidencePolicy: evidencePolicy)
            return AtomicHabitRow(id: inst.id, instance: inst, definition: def, microCommitment: micro)
        }
        .sorted { $0.definition.name.localizedCaseInsensitiveCompare($1.definition.name) == .orderedAscending }
    }

    // MARK: - Derived

    private var completedHabitCount: Int {
        habitRows.filter { $0.instance.status == .completed }.count
    }

    private var canSubmitLifeCheckIn: Bool {
        !journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - UI

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                focusCard
                atomicHabitsCard
                lifeCheckInCard
                nextStepsCard
                footer
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.largeTitle).bold()
            Text(completionHint)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            if completedHabitCount > 0 {
                Text("Atomic wins: \(completedHabitCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Focus status")
                        .font(.headline)
                    if focusStatus.completed {
                        Text("Completed—nice work. ✅")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    } else if focusStatus.isInFocusSession {
                        Text("In session")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ready when you are")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if focusStatus.targetSeconds > 0 && !focusStatus.completed {
                ProgressView(value: focusStatus.progress)
                    .tint(.blue)
            }

            Button {
                onToggleFocus()
            } label: {
                Text(focusStatus.completed ? "Start new sprint" : (focusStatus.isInFocusSession ? "Back to ritual" : "Start focus sprint"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var atomicHabitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Atomic habits")
                    .font(.headline)
                Spacer()
                Text("Quick complete")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if habitRows.isEmpty {
                Text("No atomic habits scheduled for today.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(habitRows) { row in
                    habitRow(row)
                }
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func habitRow(_ row: AtomicHabitRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.definition.name)
                        .font(.subheadline)
                        .bold()
                    if let micro = row.microCommitment {
                        Text(micro.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    statusPill(row.instance.status)
                }
                Spacer()

                if row.instance.status != .completed {
                    Button {
                        onQuickCompleteHabit(row.instance)
                    } label: {
                        Text("Complete")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusPill(_ status: AtomicHabitCompletionStatus) -> some View {
        let text: String
        let tint: Color

        switch status {
        case .notStarted:
            text = "Not started"
            tint = .gray
        case .inProgress:
            text = "In progress"
            tint = .orange
        case .completed:
            text = "Completed"
            tint = .green
        }

        return Text(text)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint)
            .clipShape(Capsule())
    }

    private var lifeCheckInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Life check-in")
                .font(.headline)

            Text(lifeCheckIn.prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Your check-in...", text: $journalText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)

            Button {
                guard canSubmitLifeCheckIn else { return }
                onSubmitLifeCheckIn(journalText)
            } label: {
                Text("Submit")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmitLifeCheckIn)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var nextStepsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Frictionless next step")
                .font(.headline)

            let suggestion: String = {
                if focusStatus.completed {
                    if habitRows.contains(where: { $0.definition.habitKind == .journalCompleted && $0.instance.status != .completed }) {
                        return "Do the journal micro-check-in next."
                    }
                    return "Lock in the win—start your next sprint."
                } else if habitRows.contains(where: { $0.definition.habitKind == .focusSessionsCompleted && $0.instance.status != .completed }) {
                    return "Finish the focus sprint micro-commitment."
                } else if habitRows.contains(where: { $0.definition.habitKind == .journalCompleted && $0.instance.status != .completed }) {
                    return "Write the journal check-in."
                } else {
                    return "Keep the ritual going—make the next small move."
                }
            }()

            Text(suggestion)
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Button {
                onNextFrictionlessAction()
            } label: {
                Text("Go")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Evidence-gated by design")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Buttons are host-wired—your app will persist, verify evidence, and route flows.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Privacy: life logging is local-first (export/delete from your host app).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#endif
