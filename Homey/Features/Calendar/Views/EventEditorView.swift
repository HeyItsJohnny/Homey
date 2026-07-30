import SwiftUI

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: EventEditorMode
    let selectedDate: Date
    let categories: [CalendarCategory]
    let members: [HomeMemberDisplay]
    let isSaving: Bool
    let isDeleting: Bool
    let errorMessage: String?
    let onSave: (EventEditorDraft) async -> Bool
    let onDelete: (() async -> Bool)?
    let onSuccess: (EventEditorCompletion) -> Void

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedCategoryId: UUID?
    @State private var assignedUserIds: Set<UUID>
    @State private var location: String
    @State private var notes: String
    @State private var localErrorMessage: String?
    @State private var isShowingDeleteConfirmation = false

    init(
        mode: EventEditorMode = .create,
        selectedDate: Date,
        categories: [CalendarCategory],
        members: [HomeMemberDisplay],
        isSaving: Bool,
        isDeleting: Bool = false,
        errorMessage: String?,
        onSave: @escaping (EventEditorDraft) async -> Bool,
        onDelete: (() async -> Bool)? = nil,
        onSuccess: @escaping (EventEditorCompletion) -> Void
    ) {
        self.mode = mode
        self.selectedDate = selectedDate
        self.categories = categories
        self.members = members
        self.isSaving = isSaving
        self.isDeleting = isDeleting
        self.errorMessage = errorMessage
        self.onSave = onSave
        self.onDelete = onDelete
        self.onSuccess = onSuccess

        let initialValues = EventEditorInitialValues.values(for: mode, selectedDate: selectedDate)
        _title = State(initialValue: initialValues.title)
        _isAllDay = State(initialValue: initialValues.isAllDay)
        _startDate = State(initialValue: initialValues.startDate)
        _endDate = State(initialValue: initialValues.endDate)
        _selectedCategoryId = State(initialValue: initialValues.categoryId)
        _assignedUserIds = State(initialValue: Set(initialValues.assignedUserIds))
        _location = State(initialValue: initialValues.location)
        _notes = State(initialValue: initialValues.notes)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && effectiveEndDate >= effectiveStartDate
            && !isSaving
            && !isDeleting
    }

    private var canDelete: Bool {
        mode.event != nil && onDelete != nil && !isSaving && !isDeleting
    }

    private var effectiveStartDate: Date {
        isAllDay ? Calendar.autoupdatingCurrent.startOfDay(for: startDate) : startDate
    }

    private var effectiveEndDate: Date {
        if isAllDay {
            return Calendar.autoupdatingCurrent.startOfDay(for: endDate)
        }

        return endDate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header

                        formCard
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 28)
                    .padding(.bottom, 34)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .disabled(isSaving || isDeleting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(HomeyDashboardTheme.warmBrown)
                        } else {
                            Text(mode.saveTitle)
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .alert("Delete Event?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Event", role: .destructive) {
                Task { await deleteEvent() }
            }
        } message: {
            Text("Delete this event? This action cannot be undone.")
        }
        .onChange(of: isAllDay) { _, newValue in
            if newValue {
                startDate = Calendar.autoupdatingCurrent.startOfDay(for: startDate)
                endDate = max(Calendar.autoupdatingCurrent.startOfDay(for: endDate), startDate)
            } else if endDate <= startDate,
                      let adjustedEnd = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: startDate) {
                endDate = adjustedEnd
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text(mode.subtitle)
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            editorTextField(
                label: "Title",
                supportingText: "Required",
                text: $title,
                axis: .horizontal
            )

            Toggle("All-Day", isOn: $isAllDay)
                .font(.headline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .tint(HomeyDashboardTheme.warmBrown)
                .frame(minHeight: 44)
                .accessibilityLabel("All-Day")

            dateSection
            categorySection
            memberAssignmentSection

            editorTextField(
                label: "Location",
                supportingText: "Optional",
                text: $location,
                axis: .horizontal
            )

            editorTextField(
                label: "Notes",
                supportingText: "Optional",
                text: $notes,
                axis: .vertical
            )

            if let message = localErrorMessage ?? errorMessage {
                EventEditorErrorBanner(message: message)
            }

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Saving event")
                } else {
                    Text(mode.saveTitle)
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(!canSave)
            .accessibilityLabel(mode.saveTitle)

            if mode.event != nil {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    HStack(spacing: 9) {
                        if isDeleting {
                            ProgressView()
                                .tint(HomeyDashboardTheme.destructiveRed)
                                .accessibilityLabel("Deleting event")
                        } else {
                            Image(systemName: "trash")
                            Text("Delete Event")
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(HomeyDashboardTheme.destructiveRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(HomeyDashboardTheme.destructiveRed.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canDelete)
                .accessibilityLabel("Delete Event")
            }
        }
        .padding(28)
        .dashboardCard(cornerRadius: 30)
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Date and Time", supportingText: isAllDay ? "All-day events use an exclusive end date at midnight after the final day." : "Choose when this event starts and ends.")

            VStack(spacing: 12) {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.compact)

                if !isAllDay {
                    DatePicker("Start Time", selection: $startDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                }

                DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.compact)

                if !isAllDay {
                    DatePicker("End Time", selection: $endDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                }
            }
            .font(.body.weight(.medium))
            .foregroundStyle(HomeyDashboardTheme.primaryText)
            .padding(16)
            .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Category", supportingText: "Optional")

            Menu {
                Button("No Category") {
                    selectedCategoryId = nil
                }

                ForEach(categories) { category in
                    Button {
                        selectedCategoryId = category.id
                    } label: {
                        Label(category.name, systemImage: category.iconName ?? "tag")
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(selectedCategoryColor)
                        .frame(width: 12, height: 12)

                    Text(selectedCategoryTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Category, \(selectedCategoryTitle)")
        }
    }

    private var memberAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Assigned Members", supportingText: "Optional")

            if members.isEmpty {
                Text("Members will appear here after they load.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(members) { member in
                        Button {
                            toggleAssignment(member.userId)
                        } label: {
                            HStack(spacing: 13) {
                                AvatarView(
                                    imageURL: member.avatarURL,
                                    initials: member.initials,
                                    size: 38,
                                    accentColor: HomeyDashboardTheme.warmBrown,
                                    borderWidth: 2,
                                    showsShadow: false,
                                    accessibilityLabel: "Avatar for \(member.displayName)"
                                )

                                Text(member.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                                Spacer()

                                Image(systemName: assignedUserIds.contains(member.userId) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(assignedUserIds.contains(member.userId) ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText.opacity(0.6))
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || isDeleting)
                        .accessibilityLabel("Assign \(member.displayName)")
                    }
                }
                .padding(.horizontal, 14)
                .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
            }
        }
    }

    private var selectedCategory: CalendarCategory? {
        categories.first { $0.id == selectedCategoryId }
    }

    private var selectedCategoryTitle: String {
        selectedCategory?.name ?? "No Category"
    }

    private var selectedCategoryColor: Color {
        Color(hex: selectedCategory?.colorHex) ?? HomeyDashboardTheme.warmBrown.opacity(0.45)
    }

    private func editorTextField(label: String, supportingText: String, text: Binding<String>, axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel(label, supportingText: supportingText)

            TextField(label, text: text, axis: axis)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, axis == .vertical ? 14 : 10)
                .frame(minHeight: axis == .vertical ? 104 : 56, alignment: axis == .vertical ? .topLeading : .center)
                .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
                .disabled(isSaving || isDeleting)
                .accessibilityLabel(label)
        }
    }

    private func sectionLabel(_ title: String, supportingText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text(supportingText)
                .font(.caption)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private func toggleAssignment(_ userId: UUID) {
        if assignedUserIds.contains(userId) {
            assignedUserIds.remove(userId)
        } else {
            assignedUserIds.insert(userId)
        }
    }

    private func save() async {
        localErrorMessage = nil

        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localErrorMessage = "Enter an event title."
            return
        }

        guard effectiveEndDate >= effectiveStartDate else {
            localErrorMessage = "The event end time must be after the start time."
            return
        }

        let draft = EventEditorDraft(
            title: title,
            notes: notes,
            location: location,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            timezone: TimeZone.autoupdatingCurrent.identifier,
            categoryId: selectedCategoryId,
            assignedUserIds: Array(assignedUserIds)
        )

        if await onSave(draft) {
            onSuccess(mode.event == nil ? .created : .updated)
            dismiss()
        }
    }

    private func deleteEvent() async {
        guard let onDelete else {
            return
        }

        localErrorMessage = nil

        if await onDelete() {
            onSuccess(.deleted)
            dismiss()
        }
    }
}

struct EventEditorDraft {
    let title: String
    let notes: String?
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let timezone: String
    let categoryId: UUID?
    let assignedUserIds: [UUID]
}

enum EventEditorMode {
    case create
    case edit(CalendarEvent)

    var event: CalendarEvent? {
        switch self {
        case .create:
            return nil
        case .edit(let event):
            return event
        }
    }

    var title: String {
        switch self {
        case .create:
            return "Add Event"
        case .edit:
            return "Event Details"
        }
    }

    var subtitle: String {
        switch self {
        case .create:
            return "Add an event to the shared Home calendar."
        case .edit:
            return "Update this shared Home calendar event."
        }
    }

    var saveTitle: String {
        switch self {
        case .create:
            return "Save Event"
        case .edit:
            return "Update Event"
        }
    }
}

enum EventEditorCompletion {
    case created
    case updated
    case deleted
}

private struct EventEditorInitialValues {
    let title: String
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date
    let categoryId: UUID?
    let assignedUserIds: [UUID]
    let location: String
    let notes: String

    static func values(for mode: EventEditorMode, selectedDate: Date, calendar: Calendar = .autoupdatingCurrent) -> EventEditorInitialValues {
        switch mode {
        case .create:
            let defaults = EventEditorDefaults.defaults(for: selectedDate, calendar: calendar)
            return EventEditorInitialValues(
                title: "",
                isAllDay: false,
                startDate: defaults.start,
                endDate: defaults.end,
                categoryId: nil,
                assignedUserIds: [],
                location: "",
                notes: ""
            )
        case .edit(let event):
            let displayEndDate: Date
            if event.isAllDay,
               let previousDay = calendar.date(byAdding: .day, value: -1, to: event.endsAt) {
                displayEndDate = max(calendar.startOfDay(for: previousDay), calendar.startOfDay(for: event.startsAt))
            } else {
                displayEndDate = event.endsAt
            }

            return EventEditorInitialValues(
                title: event.title,
                isAllDay: event.isAllDay,
                startDate: event.startsAt,
                endDate: displayEndDate,
                categoryId: event.categoryId,
                assignedUserIds: event.assignedUserIds,
                location: event.location ?? "",
                notes: event.notes ?? ""
            )
        }
    }
}

private struct EventEditorErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.destructiveRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(message)
    }
}

private enum EventEditorDefaults {
    static func defaults(for selectedDate: Date, calendar: Calendar = .autoupdatingCurrent) -> (start: Date, end: Date) {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let now = Date()
        let start: Date

        if calendar.isDate(selectedDay, inSameDayAs: now) {
            start = calendar.dateInterval(of: .hour, for: now)?.end ?? now
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDay) ?? selectedDay
        }

        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        return (start, end)
    }
}

#Preview("Event Editor") {
    EventEditorView(
        selectedDate: Date(),
        categories: [],
        members: [],
        isSaving: false,
        errorMessage: nil,
        onSave: { _ in true },
        onSuccess: { _ in }
    )
}
