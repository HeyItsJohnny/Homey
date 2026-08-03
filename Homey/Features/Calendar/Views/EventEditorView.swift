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
    let onDelete: ((EventEditorDeleteScope) async -> Bool)?
    let onSuccess: (EventEditorCompletion) -> Void

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedCategoryId: UUID?
    @State private var assignedUserIds: Set<UUID>
    @State private var location: String
    @State private var notes: String
    @State private var recurrence: CalendarRecurrenceInput
    @State private var recurrencePreset: EventRecurrencePreset
    @State private var recurrenceEndMode: RecurrenceEndMode
    @State private var localErrorMessage: String?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingCustomRecurrence = false

    init(
        mode: EventEditorMode = .create,
        selectedDate: Date,
        categories: [CalendarCategory],
        members: [HomeMemberDisplay],
        isSaving: Bool,
        isDeleting: Bool = false,
        errorMessage: String?,
        onSave: @escaping (EventEditorDraft) async -> Bool,
        onDelete: ((EventEditorDeleteScope) async -> Bool)? = nil,
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
        _recurrence = State(initialValue: initialValues.recurrence)
        _recurrencePreset = State(initialValue: EventRecurrencePreset.matching(initialValues.recurrence, startDate: initialValues.startDate))
        _recurrenceEndMode = State(initialValue: RecurrenceEndMode.mode(for: initialValues.recurrence))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && effectiveEndDate >= effectiveStartDate
            && recurrenceValidationMessage == nil
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
        }
        .sheet(isPresented: $isShowingCustomRecurrence) {
            CustomRecurrenceView(
                recurrence: recurrence,
                startDate: effectiveStartDate,
                onCancel: {
                    isShowingCustomRecurrence = false
                },
                onSave: { updatedRecurrence in
                    recurrence = updatedRecurrence
                    recurrencePreset = .custom
                    recurrenceEndMode = RecurrenceEndMode.mode(for: updatedRecurrence)
                    isShowingCustomRecurrence = false
                }
            )
        }
        .presentationDetents([.large])
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if mode.event?.isRecurring == true {
                Button("This Event Only", role: .destructive) {
                    Task { await deleteEvent(scope: .singleOccurrence) }
                }

                Button("Entire Series", role: .destructive) {
                    Task { await deleteEvent(scope: .entireSeries) }
                }
            } else {
                Button("Delete Event", role: .destructive) {
                    Task { await deleteEvent(scope: .entireSeries) }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteDialogMessage)
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
        .onChange(of: startDate) { _, newValue in
            updateRecurrenceWeekdayForStartDate(newValue)
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
            if mode.showsRecurrenceControls {
                recurrenceSection
                if recurrence.frequency != nil {
                    recurrenceEndsSection
                }
            }
            categorySection
            if mode.showsMemberAssignments {
                memberAssignmentSection
            }

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

            bottomActionButtons

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

    private var bottomActionButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
            .disabled(isSaving || isDeleting)

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
            .frame(maxWidth: .infinity)
            .disabled(!canSave)
            .accessibilityLabel(mode.saveTitle)
        }
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

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Repeat", supportingText: recurrenceSummary)

            Menu {
                ForEach(EventRecurrencePreset.allCases) { preset in
                    Button {
                        selectRecurrencePreset(preset)
                    } label: {
                        if recurrencePreset == preset {
                            Label(preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(preset.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: recurrence.iconName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 22)

                    Text(recurrencePreset.displayName)
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
            .disabled(isSaving || isDeleting)
            .accessibilityLabel("Repeat, \(recurrenceSummary)")

            if shouldShowSeriesWarning {
                Text("Updating the repeat pattern edits the series and may reset individual occurrence changes.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HomeyDashboardTheme.selectedSidebarBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var recurrenceEndsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Ends", supportingText: recurrenceEndSummary)

            VStack(alignment: .leading, spacing: 14) {
                Picker("Ends", selection: recurrenceEndModeBinding) {
                    ForEach(RecurrenceEndMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch recurrenceEndMode {
                case .never:
                    EmptyView()
                case .onDate:
                    DatePicker(
                        "End Date",
                        selection: recurrenceEndDateBinding,
                        in: Calendar.autoupdatingCurrent.startOfDay(for: effectiveStartDate)...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .font(.body.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                case .afterCount:
                    Stepper(value: recurrenceCountBinding, in: 1...999) {
                        Text("\(recurrence.count ?? 10) \((recurrence.count ?? 10) == 1 ? "occurrence" : "occurrences")")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                    }
                    .tint(HomeyDashboardTheme.warmBrown)
                }
            }
            .padding(16)
            .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
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

    private var recurrenceSummary: String {
        EventRecurrenceSummary.summary(for: recurrence, startDate: effectiveStartDate)
    }

    private var recurrenceEndSummary: String {
        switch recurrenceEndMode {
        case .never:
            return "Never ends"
        case .onDate:
            return "Ends \(EventRecurrenceSummary.endDateString(from: recurrence.endDate ?? effectiveStartDate))"
        case .afterCount:
            let count = recurrence.count ?? 10
            return "Ends after \(count) \(count == 1 ? "occurrence" : "occurrences")"
        }
    }

    private var recurrenceEndModeBinding: Binding<RecurrenceEndMode> {
        Binding(
            get: { recurrenceEndMode },
            set: { updateRecurrenceEndMode($0) }
        )
    }

    private var recurrenceEndDateBinding: Binding<Date> {
        Binding(
            get: { recurrence.endDate ?? Calendar.autoupdatingCurrent.startOfDay(for: effectiveStartDate) },
            set: { newValue in
                recurrence.endDate = max(
                    Calendar.autoupdatingCurrent.startOfDay(for: newValue),
                    Calendar.autoupdatingCurrent.startOfDay(for: effectiveStartDate)
                )
                recurrence.count = nil
            }
        )
    }

    private var recurrenceCountBinding: Binding<Int> {
        Binding(
            get: { min(max(recurrence.count ?? 10, 1), 999) },
            set: { newValue in
                recurrence.count = min(max(newValue, 1), 999)
                recurrence.endDate = nil
            }
        )
    }

    private var initialRecurrence: CalendarRecurrenceInput {
        EventEditorInitialValues.values(for: mode, selectedDate: selectedDate).recurrence
    }

    private var shouldShowSeriesWarning: Bool {
        mode.event?.isRecurring == true && recurrence != initialRecurrence
    }

    private var deleteDialogTitle: String {
        mode.event?.isRecurring == true ? "Delete Recurring Event" : "Delete Event?"
    }

    private var deleteDialogMessage: String {
        mode.event?.isRecurring == true
            ? "Choose whether to delete only this occurrence or the entire series."
            : "Delete this event? This action cannot be undone."
    }

    private var recurrenceValidationMessage: String? {
        guard recurrence.frequency != nil else {
            return nil
        }

        guard recurrence.interval >= 1 else {
            return "Repeat interval must be at least 1."
        }

        if recurrence.frequency == .weekly && (recurrence.daysOfWeek?.isEmpty ?? true) {
            return "Choose at least one weekday for weekly repeats."
        }

        if recurrenceEndMode == .onDate,
           let endDate = recurrence.endDate,
           Calendar.autoupdatingCurrent.startOfDay(for: endDate) < Calendar.autoupdatingCurrent.startOfDay(for: effectiveStartDate) {
            return "Repeat end date cannot be before the event starts."
        }

        if recurrenceEndMode == .afterCount, let count = recurrence.count, count < 1 {
            return "Repeat count must be at least 1."
        }

        if recurrenceEndMode == .afterCount, let count = recurrence.count, count > 999 {
            return "Repeat count must be 999 or fewer."
        }

        return nil
    }

    private var normalizedRecurrence: CalendarRecurrenceInput {
        guard let frequency = recurrence.frequency else {
            return CalendarRecurrenceInput()
        }

        return CalendarRecurrenceInput(
            frequency: frequency,
            interval: max(1, recurrence.interval),
            daysOfWeek: frequency == .weekly ? recurrence.daysOfWeek?.sortedByISOValue() : nil,
            endDate: recurrenceEndMode == .onDate ? recurrence.endDate : nil,
            count: recurrenceEndMode == .afterCount ? recurrence.count : nil
        )
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

    private func selectRecurrencePreset(_ preset: EventRecurrencePreset) {
        if preset == .custom {
            if recurrence.frequency == nil {
                recurrence = EventRecurrencePreset.everyWeek.recurrence(for: effectiveStartDate)
                recurrenceEndMode = .never
            }
            isShowingCustomRecurrence = true
            return
        }

        let previousEndMode = recurrenceEndMode
        let previousEndDate = recurrence.endDate
        let previousCount = recurrence.count
        recurrencePreset = preset
        recurrence = preset.recurrence(for: effectiveStartDate)

        if preset == .doesNotRepeat {
            recurrenceEndMode = .never
        } else {
            applyRecurrenceEndValues(mode: previousEndMode, endDate: previousEndDate, count: previousCount)
        }
    }

    private func updateRecurrenceWeekdayForStartDate(_ date: Date) {
        guard recurrencePreset == .everyWeek || recurrencePreset == .everyTwoWeeks else {
            if recurrenceEndMode == .onDate,
               let endDate = recurrence.endDate,
               Calendar.autoupdatingCurrent.startOfDay(for: endDate) < Calendar.autoupdatingCurrent.startOfDay(for: date) {
                recurrence.endDate = Calendar.autoupdatingCurrent.startOfDay(for: date)
            }
            return
        }

        let previousEndMode = recurrenceEndMode
        let previousEndDate = recurrence.endDate
        let previousCount = recurrence.count
        recurrence = recurrencePreset.recurrence(for: date)
        applyRecurrenceEndValues(mode: previousEndMode, endDate: previousEndDate, count: previousCount)
    }

    private func updateRecurrenceEndMode(_ mode: RecurrenceEndMode) {
        recurrenceEndMode = mode
        applyRecurrenceEndValues(mode: mode, endDate: recurrence.endDate, count: recurrence.count)
    }

    private func applyRecurrenceEndValues(mode: RecurrenceEndMode, endDate: Date?, count: Int?) {
        switch mode {
        case .never:
            recurrence.endDate = nil
            recurrence.count = nil
        case .onDate:
            recurrence.endDate = max(
                endDate.map { Calendar.autoupdatingCurrent.startOfDay(for: $0) } ?? Calendar.autoupdatingCurrent.startOfDay(for: effectiveStartDate),
                Calendar.autoupdatingCurrent.startOfDay(for: effectiveStartDate)
            )
            recurrence.count = nil
        case .afterCount:
            recurrence.endDate = nil
            recurrence.count = min(max(count ?? 10, 1), 999)
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

        if let recurrenceValidationMessage {
            localErrorMessage = recurrenceValidationMessage
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
            assignedUserIds: Array(assignedUserIds),
            recurrence: normalizedRecurrence
        )

        if await onSave(draft) {
            onSuccess(mode.event == nil ? .created : .updated)
            dismiss()
        }
    }

    private func deleteEvent(scope: EventEditorDeleteScope) async {
        guard let onDelete else {
            return
        }

        localErrorMessage = nil

        if await onDelete(scope) {
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
    let recurrence: CalendarRecurrenceInput
}

enum EventEditorMode {
    case create
    case edit(CalendarEvent, scope: EventEditorEditScope = .entireSeries)

    var event: CalendarEvent? {
        switch self {
        case .create:
            return nil
        case .edit(let event, _):
            return event
        }
    }

    var editScope: EventEditorEditScope {
        switch self {
        case .create:
            return .entireSeries
        case .edit(_, let scope):
            return scope
        }
    }

    var showsRecurrenceControls: Bool {
        switch self {
        case .create:
            return true
        case .edit(_, .entireSeries):
            return true
        case .edit(_, .singleOccurrence):
            return false
        }
    }

    var showsMemberAssignments: Bool {
        editScope != .singleOccurrence
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
        case .edit(let event, .entireSeries) where event.isRecurring:
            return "Editing Entire Series"
        case .edit(_, .singleOccurrence):
            return "Update only this occurrence."
        case .edit:
            return "Update this shared Home calendar event."
        }
    }

    var saveTitle: String {
        switch self {
        case .create:
            return "Save Event"
        case .edit(let event, .entireSeries) where event.isRecurring:
            return "Update Series"
        case .edit:
            return "Update Event"
        }
    }
}

enum EventEditorEditScope {
    case singleOccurrence
    case entireSeries
}

enum EventEditorDeleteScope {
    case singleOccurrence
    case entireSeries
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
    let recurrence: CalendarRecurrenceInput

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
                notes: "",
                recurrence: CalendarRecurrenceInput()
            )
        case .edit(let event, let scope):
            let sourceStartDate = scope == .singleOccurrence ? event.occurrenceStartsAt : event.startsAt
            let sourceEndDate = scope == .singleOccurrence ? event.occurrenceEndsAt : event.endsAt
            let displayEndDate: Date
            if event.isAllDay,
               let previousDay = calendar.date(byAdding: .day, value: -1, to: sourceEndDate) {
                displayEndDate = max(calendar.startOfDay(for: previousDay), calendar.startOfDay(for: sourceStartDate))
            } else {
                displayEndDate = sourceEndDate
            }

            return EventEditorInitialValues(
                title: event.title,
                isAllDay: event.isAllDay,
                startDate: sourceStartDate,
                endDate: displayEndDate,
                categoryId: event.categoryId,
                assignedUserIds: scope == .singleOccurrence ? [] : event.assignedUserIds,
                location: event.location ?? "",
                notes: event.notes ?? "",
                recurrence: scope == .singleOccurrence ? CalendarRecurrenceInput() : CalendarRecurrenceInput(
                    frequency: event.recurrenceFrequency,
                    interval: event.recurrenceInterval,
                    daysOfWeek: event.recurrenceDaysOfWeek,
                    endDate: event.recurrenceEndDate,
                    count: event.recurrenceCount
                )
            )
        }
    }
}

struct EventEditorErrorBanner: View {
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
