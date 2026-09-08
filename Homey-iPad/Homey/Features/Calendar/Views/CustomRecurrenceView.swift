import SwiftUI

struct CustomRecurrenceView: View {
    @Environment(\.dismiss) private var dismiss

    let startDate: Date
    let onCancel: () -> Void
    let onSave: (CalendarRecurrenceInput) -> Void

    @State private var interval: Int
    @State private var unit: CustomRecurrenceUnit
    @State private var selectedWeekdays: Set<CalendarWeekday>
    @State private var endOption: RecurrenceEndMode
    @State private var endDate: Date
    @State private var occurrenceCount: Int
    @State private var errorMessage: String?

    private let calendar: Calendar = .autoupdatingCurrent

    init(
        recurrence: CalendarRecurrenceInput,
        startDate: Date,
        onCancel: @escaping () -> Void,
        onSave: @escaping (CalendarRecurrenceInput) -> Void
    ) {
        self.startDate = startDate
        self.onCancel = onCancel
        self.onSave = onSave

        let initialUnit = CustomRecurrenceUnit(frequency: recurrence.frequency) ?? .week
        let initialWeekdays = Set(recurrence.daysOfWeek ?? [CalendarWeekday.isoWeekday(for: startDate)])
        let initialEndOption = RecurrenceEndMode.mode(for: recurrence)

        _interval = State(initialValue: min(max(recurrence.interval, 1), 99))
        _unit = State(initialValue: initialUnit)
        _selectedWeekdays = State(initialValue: initialWeekdays)
        _endOption = State(initialValue: initialEndOption)
        _endDate = State(initialValue: recurrence.endDate ?? startDate)
        _occurrenceCount = State(initialValue: min(max(recurrence.count ?? 10, 1), 999))
    }

    private var normalizedStartDate: Date {
        calendar.startOfDay(for: startDate)
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        guard interval >= 1 else {
            return "Repeat interval must be at least 1."
        }

        if unit == .week && selectedWeekdays.isEmpty {
            return "Choose at least one weekday."
        }

        if endOption == .onDate && calendar.startOfDay(for: endDate) < normalizedStartDate {
            return "End date cannot be before the event starts."
        }

        if endOption == .afterCount && occurrenceCount < 1 {
            return "Occurrences must be at least 1."
        }

        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        repeatCard
                        endsCard

                        if let message = errorMessage {
                            EventEditorErrorBanner(message: message)
                        }

                        bottomActionButtons
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 28)
                    .padding(.bottom, 34)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
        }
        .presentationDetents([.large])
        .onChange(of: unit) { _, newUnit in
            if newUnit == .week && selectedWeekdays.isEmpty {
                selectedWeekdays = [CalendarWeekday.isoWeekday(for: startDate)]
            }
        }
        .onChange(of: endOption) { _, newValue in
            normalizeEndValues(for: newValue)
        }
    }

    private var bottomActionButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }

            Button {
                save()
            } label: {
                Text("Save Repeat")
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .frame(maxWidth: .infinity)
            .disabled(!canSave)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom Repeat")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("Choose how often this event repeats.")
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private var repeatCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repeat Every")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text("Recurring events keep their local wall-clock time.")
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Stepper(value: $interval, in: 1...99) {
                Text("\(interval) \(unit.label(for: interval))")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
            }
            .tint(HomeyDashboardTheme.warmBrown)

            Picker("Unit", selection: $unit) {
                ForEach(CustomRecurrenceUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            if unit == .week {
                weekdaySelector
            }
        }
        .padding(22)
        .dashboardCard(cornerRadius: 24)
    }

    private var weekdaySelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repeat On")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            HStack(spacing: 9) {
                ForEach(CalendarWeekday.weekSelectorOrder) { weekday in
                    Button {
                        toggleWeekday(weekday)
                    } label: {
                        Text(weekday.singleLetterDisplayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(selectedWeekdays.contains(weekday) ? .white : HomeyDashboardTheme.primaryText)
                            .frame(width: 38, height: 38)
                            .background(
                                selectedWeekdays.contains(weekday) ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.appBackground.opacity(0.72),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: selectedWeekdays.contains(weekday) ? 0 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weekday.displayName)
                    .accessibilityValue(selectedWeekdays.contains(weekday) ? "Selected" : "Not selected")
                }
            }
        }
    }

    private var endsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ends")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Picker("Ends", selection: $endOption) {
                ForEach(RecurrenceEndMode.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            switch endOption {
            case .never:
                Text("This event repeats until someone updates or deletes the series.")
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            case .onDate:
                DatePicker("End Date", selection: $endDate, in: normalizedStartDate..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(.body.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
            case .afterCount:
                Stepper(value: $occurrenceCount, in: 1...999) {
                    Text("\(occurrenceCount) \(occurrenceCount == 1 ? "occurrence" : "occurrences")")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                }
                .tint(HomeyDashboardTheme.warmBrown)
            }
        }
        .padding(22)
        .dashboardCard(cornerRadius: 24)
    }

    private func toggleWeekday(_ weekday: CalendarWeekday) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }

    private func normalizeEndValues(for mode: RecurrenceEndMode) {
        switch mode {
        case .never:
            endDate = startDate
            occurrenceCount = 10
        case .onDate:
            endDate = max(calendar.startOfDay(for: endDate), normalizedStartDate)
            occurrenceCount = 10
        case .afterCount:
            endDate = startDate
            occurrenceCount = min(max(occurrenceCount, 1), 999)
        }
    }

    private func save() {
        errorMessage = nil

        if let validationMessage {
            errorMessage = validationMessage
            return
        }

        onSave(
            CalendarRecurrenceInput(
                frequency: unit.frequency,
                interval: interval,
                daysOfWeek: unit == .week ? selectedWeekdays.sortedByISOValue() : nil,
                endDate: endOption == .onDate ? endDate : nil,
                count: endOption == .afterCount ? occurrenceCount : nil
            )
        )
        dismiss()
    }
}

enum EventRecurrencePreset: String, CaseIterable, Identifiable {
    case doesNotRepeat
    case everyDay
    case everyWeek
    case everyTwoWeeks
    case everyMonth
    case everyYear
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .doesNotRepeat:
            return "Does Not Repeat"
        case .everyDay:
            return "Every Day"
        case .everyWeek:
            return "Every Week"
        case .everyTwoWeeks:
            return "Every 2 Weeks"
        case .everyMonth:
            return "Every Month"
        case .everyYear:
            return "Every Year"
        case .custom:
            return "Custom..."
        }
    }

    func recurrence(for startDate: Date) -> CalendarRecurrenceInput {
        switch self {
        case .doesNotRepeat:
            return CalendarRecurrenceInput()
        case .everyDay:
            return CalendarRecurrenceInput(frequency: .daily, interval: 1)
        case .everyWeek:
            return CalendarRecurrenceInput(frequency: .weekly, interval: 1, daysOfWeek: [CalendarWeekday.isoWeekday(for: startDate)])
        case .everyTwoWeeks:
            return CalendarRecurrenceInput(frequency: .weekly, interval: 2, daysOfWeek: [CalendarWeekday.isoWeekday(for: startDate)])
        case .everyMonth:
            return CalendarRecurrenceInput(frequency: .monthly, interval: 1)
        case .everyYear:
            return CalendarRecurrenceInput(frequency: .yearly, interval: 1)
        case .custom:
            return CalendarRecurrenceInput(frequency: .weekly, interval: 1, daysOfWeek: [CalendarWeekday.isoWeekday(for: startDate)])
        }
    }

    static func matching(_ recurrence: CalendarRecurrenceInput, startDate: Date) -> EventRecurrencePreset {
        let startWeekday = CalendarWeekday.isoWeekday(for: startDate)
        let normalizedWeekdays = recurrence.daysOfWeek?.sortedByISOValue()

        guard let frequency = recurrence.frequency else {
            return .doesNotRepeat
        }

        switch (frequency, recurrence.interval, normalizedWeekdays) {
        case (.daily, 1, _):
            return .everyDay
        case (.weekly, 1, [startWeekday]):
            return .everyWeek
        case (.weekly, 2, [startWeekday]):
            return .everyTwoWeeks
        case (.monthly, 1, _):
            return .everyMonth
        case (.yearly, 1, _):
            return .everyYear
        default:
            return .custom
        }
    }
}

enum EventRecurrenceSummary {
    static func summary(for recurrence: CalendarRecurrenceInput, startDate: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        guard let frequency = recurrence.frequency else {
            return "Does Not Repeat"
        }

        let interval = max(1, recurrence.interval)
        let base: String

        switch frequency {
        case .daily:
            base = interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            let weekdays = (recurrence.daysOfWeek?.isEmpty == false ? recurrence.daysOfWeek : [CalendarWeekday.isoWeekday(for: startDate)]) ?? []
            let weekdayText = weekdaySummary(weekdays.sortedByISOValue())
            base = "\(interval == 1 ? "Every week" : "Every \(interval) weeks") on \(weekdayText)"
        case .monthly:
            base = interval == 1 ? "Every month" : "Every \(interval) months"
        case .yearly:
            base = interval == 1 ? "Every year" : "Every \(interval) years"
        }

        if let endDate = recurrence.endDate {
            return "\(base) · Ends \(endDateString(from: endDate))"
        }

        if let count = recurrence.count {
            return "\(base) · Ends after \(count) \(count == 1 ? "occurrence" : "occurrences")"
        }

        return "\(base) · Never ends"
    }

    private static func weekdaySummary(_ weekdays: [CalendarWeekday]) -> String {
        switch weekdays.count {
        case 0:
            return "the selected day"
        case 1:
            return weekdays[0].displayName
        case 2:
            return "\(weekdays[0].displayName) and \(weekdays[1].displayName)"
        default:
            let leading = weekdays.dropLast().map(\.displayName).joined(separator: ", ")
            return "\(leading), and \(weekdays.last?.displayName ?? "")"
        }
    }

    static func endDateString(from date: Date) -> String {
        endDateFormatter.string(from: date)
    }

    private static let endDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

private enum CustomRecurrenceUnit: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    init?(frequency: CalendarRecurrenceFrequency?) {
        switch frequency {
        case .daily:
            self = .day
        case .weekly:
            self = .week
        case .monthly:
            self = .month
        case .yearly:
            self = .year
        case nil:
            return nil
        }
    }

    var frequency: CalendarRecurrenceFrequency {
        switch self {
        case .day:
            return .daily
        case .week:
            return .weekly
        case .month:
            return .monthly
        case .year:
            return .yearly
        }
    }

    var displayName: String {
        switch self {
        case .day:
            return "Day"
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .year:
            return "Year"
        }
    }

    func label(for interval: Int) -> String {
        let base = rawValue
        return interval == 1 ? base : "\(base)s"
    }
}

enum RecurrenceEndMode: String, CaseIterable, Identifiable {
    case never
    case onDate
    case afterCount

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never:
            return "Never"
        case .onDate:
            return "On Date"
        case .afterCount:
            return "After Occurrences"
        }
    }

    static func mode(for recurrence: CalendarRecurrenceInput) -> RecurrenceEndMode {
        if recurrence.endDate != nil {
            return .onDate
        }

        if recurrence.count != nil {
            return .afterCount
        }

        return .never
    }
}

extension CalendarRecurrenceInput {
    var iconName: String {
        frequency == nil ? "repeat" : "repeat.circle.fill"
    }
}

extension CalendarWeekday {
    static let weekSelectorOrder: [CalendarWeekday] = [
        .sunday,
        .monday,
        .tuesday,
        .wednesday,
        .thursday,
        .friday,
        .saturday
    ]

    static func isoWeekday(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> CalendarWeekday {
        let weekday = calendar.component(.weekday, from: date)
        let isoValue = weekday == 1 ? 7 : weekday - 1
        return CalendarWeekday(rawValue: isoValue) ?? .monday
    }

    var singleLetterDisplayName: String {
        switch self {
        case .sunday:
            return "S"
        case .monday:
            return "M"
        case .tuesday:
            return "T"
        case .wednesday:
            return "W"
        case .thursday:
            return "T"
        case .friday:
            return "F"
        case .saturday:
            return "S"
        }
    }
}

extension Sequence where Element == CalendarWeekday {
    func sortedByISOValue() -> [CalendarWeekday] {
        sorted { $0.rawValue < $1.rawValue }
    }
}

#Preview("Custom Recurrence") {
    CustomRecurrenceView(
        recurrence: CalendarRecurrenceInput(frequency: .weekly, interval: 1, daysOfWeek: [.monday]),
        startDate: Date(),
        onCancel: {},
        onSave: { _ in }
    )
}
