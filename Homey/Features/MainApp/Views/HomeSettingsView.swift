import SwiftUI

struct HomeSettingsView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService

    var onClose: () -> Void = {}
    var onShowCalendarCategories: () -> Void = {}

    @State private var homeName = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var weekStartsOn = WeekStartOption.sunday.rawValue
    @State private var originalValues: HomeSettingsValues?
    @State private var isShowingTimezonePicker = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var isShowingSaveError = false
    @State private var isShowingDiscardConfirmation = false

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var trimmedHomeName: String {
        homeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentValues: HomeSettingsValues {
        HomeSettingsValues(
            name: trimmedHomeName,
            timezone: timezone,
            weekStartsOn: weekStartsOn
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let originalValues else {
            return false
        }

        return currentValues != originalValues
    }

    private var canSave: Bool {
        hasUnsavedChanges && !trimmedHomeName.isEmpty && !homeService.isLoading
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if selectedHome == nil {
                        missingHomeState
                    } else {
                        settingsCard
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: selectedHome?.id) {
            loadSelectedHome()
        }
        .sheet(isPresented: $isShowingTimezonePicker) {
            TimeZonePickerView(selectedTimezone: $timezone)
        }
        .alert("Unable to Save Changes", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) {
                onClose()
            }
        } message: {
            Text("Your changes have not been saved.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home Settings")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text("Manage the basic details and preferences for your home.")
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            Button {
                closeOrConfirmDiscard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var missingHomeState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unable to load Home Settings.")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text("Please choose a Home and try again.")
                .font(.body)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: 30)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 18) {
                DashboardSettingsTextField(
                    label: "Home Name",
                    supportingText: "This name is shown to everyone in your home.",
                    text: $homeName
                )

                DashboardSettingsPickerButton(
                    label: "Time Zone",
                    supportingText: "Used for calendars, chores, meals, reminders, and notifications.",
                    value: timezoneDisplayName(for: timezone),
                    accessibilityLabel: "Time Zone selector"
                ) {
                    isShowingTimezonePicker = true
                }

                DashboardWeekStartPicker(selection: $weekStartsOn)

                DashboardSettingsNavigationRow(
                    title: "Calendar Categories",
                    supportingText: "Manage the shared colors and icons used for events.",
                    systemImage: "tag.fill",
                    action: onShowCalendarCategories
                )
            }

            if let successMessage {
                DashboardSettingsSuccessBanner(message: successMessage)
                    .transition(.opacity)
            }

            if trimmedHomeName.isEmpty && hasUnsavedChanges {
                DashboardSettingsErrorBanner(message: "Home name is required.")
            }

            Button {
                Task {
                    await saveChanges()
                }
            } label: {
                if homeService.isLoading {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Saving changes")
                } else {
                    Text("Save Changes")
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(!canSave)
            .accessibilityLabel("Save Changes")
        }
        .padding(28)
        .dashboardCard(cornerRadius: 30)
    }

    // MARK: - Actions

    private func loadSelectedHome() {
        guard let selectedHome else {
            return
        }

        let loadedValues = HomeSettingsValues(
            name: selectedHome.name,
            timezone: selectedHome.timezone ?? TimeZone.current.identifier,
            weekStartsOn: WeekStartOption(rawValue: selectedHome.weekStartsOn)?.rawValue ?? WeekStartOption.sunday.rawValue
        )

        homeName = loadedValues.name
        timezone = loadedValues.timezone
        weekStartsOn = loadedValues.weekStartsOn
        originalValues = loadedValues
        successMessage = nil
        errorMessage = nil
    }

    private func saveChanges() async {
        guard canSave else {
            return
        }

        guard let selectedHome else {
            errorMessage = "Unable to load Home Settings. Please choose a Home and try again."
            isShowingSaveError = true
            return
        }

        guard let userID = authenticationService.currentUser?.id else {
            errorMessage = "Unable to identify the current user."
            isShowingSaveError = true
            return
        }

        successMessage = nil
        let didSave = await homeService.updateHomeSettings(
            homeID: selectedHome.id,
            name: homeName,
            timezone: timezone,
            weekStartsOn: weekStartsOn,
            userID: userID
        )

        if didSave {
            let savedValues = currentValues
            homeName = savedValues.name
            originalValues = savedValues

            withAnimation(.easeInOut(duration: 0.2)) {
                successMessage = "Changes saved"
            }
        } else {
            errorMessage = homeService.errorMessage ?? "Unable to save Home settings."
            isShowingSaveError = true
        }
    }

    private func closeOrConfirmDiscard() {
        if hasUnsavedChanges {
            isShowingDiscardConfirmation = true
        } else {
            onClose()
        }
    }

    private func timezoneDisplayName(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else {
            return identifier
        }

        let city = identifier
            .split(separator: "/")
            .last
            .map { String($0).replacingOccurrences(of: "_", with: " ") } ?? identifier
        let offset = timeZone.secondsFromGMT() / 3600
        let offsetText = offset >= 0 ? "GMT+\(offset)" : "GMT\(offset)"
        return "\(city) (\(identifier), \(offsetText))"
    }
}

private struct HomeSettingsValues: Equatable {
    let name: String
    let timezone: String
    let weekStartsOn: Int
}

private enum WeekStartOption: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sunday:
            "Sunday"
        case .monday:
            "Monday"
        }
    }
}

private struct DashboardSettingsTextField: View {
    let label: String
    let supportingText: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingsLabel(label, supportingText: supportingText)

            TextField(label, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
                .accessibilityLabel("Home Name field")
        }
    }
}

private struct DashboardSettingsPickerButton: View {
    let label: String
    let supportingText: String
    let value: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingsLabel(label, supportingText: supportingText)

            Button(action: action) {
                HStack(spacing: 12) {
                    Text(value)
                        .font(.body.weight(.medium))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.down")
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
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

private struct DashboardSettingsNavigationRow: View {
    let title: String
    let supportingText: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(HomeyDashboardTheme.selectedSidebarBackground)
                        .frame(width: 44, height: 44)

                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Text(supportingText)
                        .font(.caption)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.72))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct DashboardWeekStartPicker: View {
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingsLabel(
                "Week Starts On",
                supportingText: "Controls how weekly calendars and planners are displayed."
            )

            HStack(spacing: 10) {
                ForEach(WeekStartOption.allCases) { option in
                    Button {
                        selection = option.rawValue
                    } label: {
                        Text(option.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selection == option.rawValue ? .white : HomeyDashboardTheme.warmBrown)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(
                                selection == option.rawValue ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.selectedSidebarBackground,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Week Starts On selector")
        }
    }
}

private struct DashboardSettingsSuccessBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HomeyDashboardTheme.sageAccent)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.sageAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(message)
    }
}

private struct DashboardSettingsErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.destructiveRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(message)
    }
}

struct DashboardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                HomeyDashboardTheme.warmBrown.opacity(isEnabled ? 1 : 0.38),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .shadow(
                color: HomeyDashboardTheme.warmBrown.opacity(isEnabled && !configuration.isPressed ? 0.18 : 0.06),
                radius: 14,
                x: 0,
                y: 8
            )
            .opacity(configuration.isPressed ? 0.90 : 1)
    }
}

private func settingsLabel(_ title: String, supportingText: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.primaryText)

        Text(supportingText)
            .font(.caption)
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
    }
}

private struct TimeZonePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTimezone: String
    @State private var searchText = ""

    private var filteredTimezones: [String] {
        let identifiers = TimeZone.knownTimeZoneIdentifiers.sorted()
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSearch.isEmpty else {
            return identifiers
        }

        return identifiers.filter { identifier in
            identifier.localizedCaseInsensitiveContains(trimmedSearch)
                || friendlyName(for: identifier).localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredTimezones, id: \.self) { identifier in
                Button {
                    selectedTimezone = identifier
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(friendlyName(for: identifier))
                                .foregroundStyle(HomeyDashboardTheme.primaryText)

                            Text(identifier)
                                .font(.caption)
                                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        }

                        Spacer()

                        if selectedTimezone == identifier {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Time Zone")
            .searchable(text: $searchText, prompt: "Search time zones")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func friendlyName(for identifier: String) -> String {
        identifier
            .split(separator: "/")
            .last
            .map { String($0).replacingOccurrences(of: "_", with: " ") } ?? identifier
    }
}

#Preview("Home Settings") {
    HomeSettingsView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}
