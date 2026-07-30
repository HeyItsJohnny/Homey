import SwiftUI

struct MyAccountView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService

    var onClose: () -> Void = {}
    var onShowInvitations: () -> Void = {}

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var displayName = ""
    @State private var originalValues: AccountProfileValues?
    @State private var isDisplayNameCustomized = false
    @State private var isUpdatingDisplayNameProgrammatically = false
    @State private var isLoadingProfile = true
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var isShowingSaveError = false

    private var pendingInvitationCount: Int {
        homeService.myPendingInvitations.count
    }

    private var currentValues: AccountProfileValues {
        AccountProfileValues(
            firstName: firstName,
            lastName: lastName,
            displayName: displayName
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let originalValues else {
            return false
        }

        return currentValues != originalValues
    }

    private var canSave: Bool {
        hasUnsavedChanges
            && !currentValues.firstName.isEmpty
            && !currentValues.lastName.isEmpty
            && !currentValues.displayName.isEmpty
            && !authenticationService.isLoading
            && !isLoadingProfile
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if isLoadingProfile {
                        loadingCard
                    } else {
                        profileCard
                        invitationsCard
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
        .task(id: authenticationService.currentUser?.id) {
            await loadAccountData()
        }
        .onChange(of: firstName) { _, _ in
            updateGeneratedDisplayNameIfNeeded()
        }
        .onChange(of: lastName) { _, _ in
            updateGeneratedDisplayNameIfNeeded()
        }
        .onChange(of: displayName) { _, newValue in
            handleDisplayNameChange(newValue)
        }
        .alert("Unable to Save Account", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "We could not update your account. Please try again.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("My Account")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Manage your personal profile and account preferences.")
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            Button {
                onClose()
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

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(HomeyDashboardTheme.warmBrown)
                .accessibilityLabel("Loading account information")

            Text("Loading account information...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .dashboardCard(cornerRadius: 30)
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeading(
                title: "Profile Information",
                subtitle: "These details are saved to your Homey profile."
            )

            VStack(spacing: 18) {
                MyAccountTextField(
                    label: "First Name",
                    supportingText: "Your given name.",
                    text: $firstName,
                    textContentType: .givenName,
                    accessibilityLabel: "First Name field"
                )

                MyAccountTextField(
                    label: "Last Name",
                    supportingText: "Your family name.",
                    text: $lastName,
                    textContentType: .familyName,
                    accessibilityLabel: "Last Name field"
                )

                MyAccountTextField(
                    label: "Display Name",
                    supportingText: "This is how your name appears in Homey.",
                    text: $displayName,
                    textContentType: .name,
                    accessibilityLabel: "Display Name field"
                )
            }

            accountInformation

            if let successMessage {
                MyAccountStatusBanner(message: successMessage)
                    .transition(.opacity)
            }

            if currentValues.firstName.isEmpty && hasUnsavedChanges {
                MyAccountErrorBanner(message: "Enter your first name.")
            } else if currentValues.lastName.isEmpty && hasUnsavedChanges {
                MyAccountErrorBanner(message: "Enter your last name.")
            } else if currentValues.displayName.isEmpty && hasUnsavedChanges {
                MyAccountErrorBanner(message: "Enter a display name.")
            }

            Button {
                Task {
                    await saveAccount()
                }
            } label: {
                if authenticationService.isLoading {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Saving account")
                } else {
                    Text("Save Changes")
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(!canSave)
            .accessibilityLabel("Save Account Changes")
        }
        .padding(28)
        .dashboardCard(cornerRadius: 30)
    }

    private var accountInformation: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading(
                title: "Account Information",
                subtitle: "Email changes are not available yet."
            )

            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .accessibilityHidden(true)

                Text(authenticationService.currentUser?.email ?? "Email unavailable")
                    .font(.body.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(1)

                Spacer()

                Text("Read Only")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(HomeyDashboardTheme.appBackground.opacity(0.72), in: Capsule())
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
            .accessibilityLabel("Email, \(authenticationService.currentUser?.email ?? "unavailable"), read only")
        }
    }

    private var invitationsCard: some View {
        Button(action: onShowInvitations) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(HomeyDashboardTheme.selectedSidebarBackground)
                        .frame(width: 54, height: 54)

                    Image(systemName: "envelope.badge")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text("Home Invitations")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)

                        if pendingInvitationCount > 0 {
                            Text("\(pendingInvitationCount) Pending")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                        }
                    }

                    Text("View invitations to join another home.")
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                Spacer()

                if homeService.isLoadingMyInvitations {
                    ProgressView()
                        .tint(HomeyDashboardTheme.warmBrown)
                        .accessibilityLabel("Loading Home invitations")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.7))
                }
            }
            .padding(22)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .dashboardCard(cornerRadius: 28)
        .accessibilityLabel("Home Invitations, \(pendingInvitationCount) pending")
    }

    private func sectionHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private func loadAccountData() async {
        guard let userID = authenticationService.currentUser?.id else {
            isLoadingProfile = false
            errorMessage = "Your session has expired. Please sign in again."
            isShowingSaveError = true
            return
        }

        isLoadingProfile = true
        await authenticationService.refreshCurrentUserProfile()
        populateProfileFields()
        await homeService.loadMyPendingInvitations(for: userID)
        isLoadingProfile = false
    }

    private func populateProfileFields() {
        guard let profile = authenticationService.currentUser else {
            return
        }

        let loadedValues = AccountProfileValues(
            firstName: profile.firstName ?? "",
            lastName: profile.lastName ?? "",
            displayName: profile.displayName ?? ""
        )

        firstName = loadedValues.firstName
        lastName = loadedValues.lastName
        let generatedName = ProfileNameFormatter.generatedDisplayName(firstName: loadedValues.firstName, lastName: loadedValues.lastName)
        isDisplayNameCustomized = !loadedValues.displayName.isEmpty && loadedValues.displayName != generatedName
        setDisplayNameProgrammatically(loadedValues.displayName)
        originalValues = loadedValues
        successMessage = nil
        errorMessage = nil
    }

    private func saveAccount() async {
        guard canSave else {
            return
        }

        successMessage = nil
        errorMessage = nil

        let didSave = await authenticationService.updateCurrentUserProfile(
            firstName: firstName,
            lastName: lastName,
            displayName: displayName
        )

        if didSave {
            populateProfileFields()
            withAnimation(.easeInOut(duration: 0.2)) {
                successMessage = "Account updated."
            }
        } else {
            errorMessage = authenticationService.errorMessage ?? "We could not update your account. Please try again."
            isShowingSaveError = true
        }
    }

    private func updateGeneratedDisplayNameIfNeeded() {
        guard !isDisplayNameCustomized else {
            return
        }

        setDisplayNameProgrammatically(
            ProfileNameFormatter.generatedDisplayName(firstName: firstName, lastName: lastName)
        )
    }

    private func handleDisplayNameChange(_ newValue: String) {
        guard !isUpdatingDisplayNameProgrammatically else {
            return
        }

        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isDisplayNameCustomized = false
            updateGeneratedDisplayNameIfNeeded()
            return
        }

        let generatedValue = ProfileNameFormatter.generatedDisplayName(firstName: firstName, lastName: lastName)
        isDisplayNameCustomized = newValue.trimmingCharacters(in: .whitespacesAndNewlines) != generatedValue
    }

    private func setDisplayNameProgrammatically(_ value: String) {
        isUpdatingDisplayNameProgrammatically = true
        displayName = value
        isUpdatingDisplayNameProgrammatically = false
    }
}

private struct AccountProfileValues: Equatable {
    let firstName: String
    let lastName: String
    let displayName: String

    init(firstName: String, lastName: String, displayName: String) {
        self.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MyAccountTextField: View {
    let label: String
    let supportingText: String
    @Binding var text: String
    let textContentType: UITextContentType
    let accessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            TextField(label, text: $text)
                .textContentType(textContentType)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
                .accessibilityLabel(accessibilityLabel)
        }
    }
}

private struct MyAccountStatusBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
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

private struct MyAccountErrorBanner: View {
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

#Preview("My Account") {
    MyAccountView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}
