import SwiftUI

private enum MainTab: Hashable { case home, calendar, meals, chores, groceries }

struct MainTabView: View {
    @State private var selection: MainTab = .home
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView(navigate: navigate) }.tabItem { Label("Home", systemImage: "house.fill") }.tag(MainTab.home)
            NavigationStack { CalendarRootView() }.tabItem { Label("Calendar", systemImage: "calendar") }.tag(MainTab.calendar)
            ChoresRootView().tabItem { Label("Chores", systemImage: "checklist") }.tag(MainTab.chores)
            MealsRootView().tabItem { Label("Meals", systemImage: "fork.knife") }.tag(MainTab.meals)
            NavigationStack { GroceriesView(isActive: selection == .groceries) }.tabItem { Label("Groceries", systemImage: "cart") }.tag(MainTab.groceries)
        }.tint(HomeyColors.primary)
    }
    private func tab(_ title: String, _ symbol: String) -> some View { NavigationStack { FeaturePlaceholderView(title: title, symbol: symbol) } }
    private func navigate(_ destination: DashboardDestination) { switch destination { case .calendar: selection = .calendar; case .meals: selection = .meals; case .chores: selection = .chores; case .groceries: selection = .groceries } }
}

private struct FeaturePlaceholderView: View {
    @EnvironmentObject private var appSession: AppSession
    let title: String; let symbol: String
    var body: some View {
        ZStack {
            HomeyBackground()
            VStack(spacing: 18) {
                Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(HomeyColors.primary).frame(width: 72, height: 72).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22))
                Text(title).font(HomeyTypography.hero).foregroundStyle(HomeyColors.text)
                Text("Phase 1 foundation is ready.").foregroundStyle(HomeyColors.secondaryText)
                VStack(alignment: .leading, spacing: 10) {
                    Label(appSession.activeHome?.name ?? "No active Home", systemImage: "house")
                    Label(appSession.currentUser?.preferredDisplayName ?? "No profile", systemImage: "person")
                    if let role = appSession.activeRole { Label(role.displayName, systemImage: "person.badge.key") }
                    Label(appSession.activeTimezone.identifier, systemImage: "globe")
                }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).homeyCard()
            }.padding(20)
        }.navigationTitle(title)
    }
}

struct ProfileSheet: View {
    @EnvironmentObject private var appSession: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var isRefreshingProfile = false
    @State private var statusMessage: String?
    @State private var profileError: String?
    @State private var adminPinStatus: HomeAdminPinStatus?
    @State private var isLoadingAdminPinStatus = false
    @State private var adminPinStatusError: String?
    @State private var showingAdminPinManager = false
    private let adminPinService = AdminPinService()

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if isRefreshingProfile {
                            HStack(spacing: 10) { ProgressView(); Text("Refreshing profile…") }
                                .font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let statusMessage {
                            Label(statusMessage, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium)).foregroundStyle(HomeyColors.success)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(HomeyColors.success.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                        }
                        if let profileError { HomeyErrorView(message: profileError).padding(14).background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16)) }
                        profileCard
                        accountCard
                        homeCard
                        signOutButton
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: appSession.currentUser?.id) {
                await refreshProfile()
                await refreshInvitations()
            }
            .task(id: appSession.activeHome?.id) {
                await refreshAdminPinStatus()
            }
            .sheet(isPresented: $showingEditor) {
                EditProfileView { message in
                    statusMessage = message
                    profileError = nil
                }
            }
            .sheet(isPresented: $showingAdminPinManager, onDismiss: {
                Task { await refreshAdminPinStatus() }
            }) {
                if let homeID = appSession.activeHome?.id,
                   let adminPinStatus,
                   adminPinStatus.canManagePIN {
                    AdminPinManagementSheet(
                        homeID: homeID,
                        initialStatus: adminPinStatus
                    ) { updatedStatus in
                        self.adminPinStatus = updatedStatus
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var profileCard: some View {
        VStack(spacing: 14) {
            ProfileAvatarView(profile: appSession.currentUser, size: 92)

            VStack(spacing: 5) {
                Text(appSession.currentUser?.preferredDisplayName ?? "Homey Member")
                    .font(HomeyTypography.title)
                    .foregroundStyle(HomeyColors.text)
                    .multilineTextAlignment(.center)

                Text(appSession.currentUser?.email ?? "Email unavailable")
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Button("Edit Profile") {
                statusMessage = nil
                showingEditor = true
            }
            .buttonStyle(.borderedProminent)
            .tint(HomeyColors.primary)
        }
        .frame(maxWidth: .infinity)
        .homeyCard()
    }

    private func refreshProfile() async {
        guard appSession.currentUser != nil else {
            profileError = "Your session has expired. Please sign in again."
            return
        }
        isRefreshingProfile = true
        let loaded = await appSession.authentication.refreshCurrentUserProfile()
        isRefreshingProfile = false
        if !loaded { profileError = appSession.authentication.errorMessage ?? "We couldn't load your profile." }
    }

    private func refreshInvitations() async {
        guard let userID = appSession.currentUser?.id else { return }
        await appSession.homes.loadMyPendingInvitations(userID: userID, forceRefresh: true)
    }

    private func refreshAdminPinStatus() async {
        adminPinStatus = nil
        adminPinStatusError = nil
        guard let homeID = appSession.activeHome?.id else { return }
        isLoadingAdminPinStatus = true
        defer {
            if appSession.activeHome?.id == homeID {
                isLoadingAdminPinStatus = false
            }
        }

        do {
            let status = try await adminPinService.status(homeID: homeID)
            guard appSession.activeHome?.id == homeID else { return }
            adminPinStatus = status
        } catch {
            guard appSession.activeHome?.id == homeID else { return }
            adminPinStatusError = error.localizedDescription
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            profileSectionTitle("Account", subtitle: "Manage invitations connected to your account")

            NavigationLink {
                HomeInvitationsView()
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "envelope.badge")
                        .foregroundStyle(HomeyColors.primary)
                        .frame(width: 40, height: 40)
                        .background(HomeyColors.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Invites")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeyColors.text)
                        Text(invitationDetail)
                            .font(.caption)
                            .foregroundStyle(HomeyColors.secondaryText)
                    }
                    Spacer()
                    if !appSession.homes.myPendingInvitations.isEmpty {
                        Text("\(appSession.homes.myPendingInvitations.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(HomeyColors.primary, in: Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let adminPinStatus, adminPinStatus.canManagePIN {
                Divider()
                Button {
                    showingAdminPinManager = true
                } label: {
                    profileNavigationRow(
                        "iPad Admin PIN",
                        detail: adminPinStatus.hasPIN ? "Configured" : "Not Set",
                        icon: "lock.shield.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("iPad Admin PIN, \(adminPinStatus.hasPIN ? "Configured" : "Not Set")")
            } else if isLoadingAdminPinStatus,
                      appSession.activeRole == .owner || appSession.activeRole == .admin {
                Divider()
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking iPad Admin PIN…")
                        .font(.caption)
                        .foregroundStyle(HomeyColors.secondaryText)
                }
            } else if let adminPinStatusError,
                      appSession.activeRole == .owner || appSession.activeRole == .admin {
                Divider()
                Text(adminPinStatusError)
                    .font(.caption)
                    .foregroundStyle(HomeyColors.danger)
            }
        }
        .homeyCard()
    }

    private var invitationDetail: String {
        if appSession.homes.isLoadingMyInvitations { return "Checking for pending invitations…" }
        if appSession.homes.myInvitationsErrorMessage != nil { return "Unable to load invitations — tap to retry" }
        let count = appSession.homes.myPendingInvitations.count
        if count == 0 { return "No pending invitations" }
        return "\(count) pending invitation\(count == 1 ? "" : "s")"
    }

    private var homeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            profileSectionTitle("Active Home", subtitle: "Your current household and access")

            if let home = appSession.activeHome {
                HStack(spacing: 13) {
                    Image(systemName: "house.fill")
                        .font(.headline)
                        .foregroundStyle(HomeyColors.primary)
                        .frame(width: 44, height: 44)
                        .background(HomeyColors.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(home.name).font(.headline).foregroundStyle(HomeyColors.text)
                        Text(appSession.activeRole?.displayName ?? "Role unavailable")
                            .font(.caption).foregroundStyle(HomeyColors.secondaryText)
                    }
                    Spacer()
                }

                if appSession.homes.homes.count > 1 {
                    Divider()
                    Button {
                        dismiss()
                        appSession.chooseAnotherHome()
                    } label: {
                        profileNavigationRow("Change Home", detail: "Choose another household", icon: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("No Home is currently selected.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
            }
        }
        .homeyCard()
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            Task {
                dismiss()
                await appSession.signOut()
            }
        } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.headline)
                .foregroundStyle(HomeyColors.danger)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
                .overlay {
                    RoundedRectangle(cornerRadius: HomeyCornerRadius.field)
                        .stroke(HomeyColors.danger.opacity(0.30))
                }
        }
        .buttonStyle(.plain)
    }

    private func profileSectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
            Text(subtitle).font(.caption).foregroundStyle(HomeyColors.secondaryText)
        }
    }

    private func profileNavigationRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(HomeyColors.primary)
                .frame(width: 40, height: 40)
                .background(HomeyColors.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text)
                Text(detail).font(.caption).foregroundStyle(HomeyColors.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private enum AdminPinEntryStep {
    case enter
    case confirm
}

private struct AdminPinManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let homeID: UUID
    let onStatusChanged: (HomeAdminPinStatus) -> Void

    @State private var status: HomeAdminPinStatus
    @State private var isEditingPIN: Bool
    @State private var entryStep: AdminPinEntryStep = .enter
    @State private var newPIN = ""
    @State private var confirmationPIN = ""
    @State private var isSaving = false
    @State private var isRemoving = false
    @State private var isShowingRemoveConfirmation = false
    @State private var errorMessage: String?

    private let service = AdminPinService()

    init(
        homeID: UUID,
        initialStatus: HomeAdminPinStatus,
        onStatusChanged: @escaping (HomeAdminPinStatus) -> Void
    ) {
        self.homeID = homeID
        self.onStatusChanged = onStatusChanged
        _status = State(initialValue: initialStatus)
        _isEditingPIN = State(initialValue: !initialStatus.hasPIN)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let errorMessage {
                            HomeyErrorView(message: errorMessage)
                        }

                        if isEditingPIN {
                            pinEntryCard
                        } else {
                            managementCard
                        }
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("iPad Admin PIN")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving || isRemoving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditingPIN && status.hasPIN ? "Cancel" : "Done") {
                        if isEditingPIN && status.hasPIN {
                            cancelPINEntry()
                        } else {
                            clearPINEntry()
                            dismiss()
                        }
                    }
                    .disabled(isSaving || isRemoving)
                }
            }
        }
        .presentationDetents([.large])
        .onDisappear(perform: clearPINEntry)
        .confirmationDialog(
            "Remove iPad Admin PIN?",
            isPresented: $isShowingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove PIN", role: .destructive) {
                Task { await removePIN() }
            }
        } message: {
            Text("This will prevent this PIN from unlocking the shared iPad Admin area.")
        }
    }

    private var managementCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: status.hasPIN ? "lock.shield.fill" : "lock.slash.fill")
                    .font(.title2)
                    .foregroundStyle(status.hasPIN ? HomeyColors.success : HomeyColors.secondaryText)
                    .frame(width: 48, height: 48)
                    .background((status.hasPIN ? HomeyColors.success : HomeyColors.secondaryText).opacity(0.10), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("iPad Admin PIN")
                        .font(.headline)
                        .foregroundStyle(HomeyColors.text)
                    Text(status.hasPIN ? "Configured" : "Not Set")
                        .font(.subheadline)
                        .foregroundStyle(HomeyColors.secondaryText)
                }
            }

            Text("This personal PIN unlocks the shared iPad Admin area for your account. Homey never displays your existing PIN.")
                .font(.subheadline)
                .foregroundStyle(HomeyColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if status.hasPIN {
                Button("Change PIN") {
                    beginPINEntry()
                }
                .buttonStyle(HomeyButtonStyle())

                Button("Remove PIN", role: .destructive) {
                    isShowingRemoveConfirmation = true
                }
                .font(.headline)
                .foregroundStyle(HomeyColors.danger)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(HomeyColors.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .disabled(isRemoving)
            } else {
                Button("Set PIN") {
                    beginPINEntry()
                }
                .buttonStyle(HomeyButtonStyle())
            }
        }
        .homeyCard()
    }

    private var pinEntryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entryStep == .enter ? "Enter New PIN" : "Confirm PIN")
                    .font(HomeyTypography.headline)
                    .foregroundStyle(HomeyColors.text)
                Text(entryStep == .enter ? "Choose exactly four numeric digits." : "Enter the same four digits again.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
            }

            if entryStep == .enter {
                pinField("New PIN", text: $newPIN)

                Button("Continue") {
                    errorMessage = nil
                    entryStep = .confirm
                }
                .buttonStyle(HomeyButtonStyle())
                .disabled(!AdminPinService.isValid(newPIN))
                .opacity(AdminPinService.isValid(newPIN) ? 1 : 0.55)
            } else {
                pinField("Confirm PIN", text: $confirmationPIN)

                Button {
                    Task { await savePIN() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Saving…" : "Save PIN")
                    }
                }
                .buttonStyle(HomeyButtonStyle())
                .disabled(!AdminPinService.isValid(confirmationPIN) || isSaving)
                .opacity(AdminPinService.isValid(confirmationPIN) && !isSaving ? 1 : 0.55)

                Button("Back") {
                    confirmationPIN = ""
                    errorMessage = nil
                    entryStep = .enter
                }
                .buttonStyle(.plain)
                .foregroundStyle(HomeyColors.primary)
                .frame(maxWidth: .infinity)
                .disabled(isSaving)
            }
        }
        .homeyCard()
    }

    private func pinField(_ title: String, text: Binding<String>) -> some View {
        SecureField("4-digit PIN", text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .tracking(12)
            .privacySensitive()
            .homeyTextField()
            .accessibilityLabel(title)
            .onChange(of: text.wrappedValue) { _, value in
                let normalized = AdminPinService.normalized(value)
                if value != normalized { text.wrappedValue = normalized }
            }
    }

    private func beginPINEntry() {
        clearPINEntry()
        errorMessage = nil
        isEditingPIN = true
    }

    private func cancelPINEntry() {
        clearPINEntry()
        errorMessage = nil
        isEditingPIN = false
    }

    private func clearPINEntry() {
        newPIN = ""
        confirmationPIN = ""
        entryStep = .enter
    }

    private func savePIN() async {
        guard !isSaving,
              AdminPinService.isValid(newPIN),
              AdminPinService.isValid(confirmationPIN) else {
            errorMessage = AdminPinServiceError.invalidPIN.localizedDescription
            return
        }
        guard newPIN == confirmationPIN else {
            errorMessage = "PINs do not match. Please try again."
            confirmationPIN = ""
            return
        }

        isSaving = true
        errorMessage = nil
        let submittedPIN = newPIN
        defer {
            isSaving = false
            clearPINEntry()
        }

        do {
            try await service.setPIN(submittedPIN, homeID: homeID)
            let updatedStatus = HomeAdminPinStatus(hasPIN: true, canManagePIN: true)
            status = updatedStatus
            onStatusChanged(updatedStatus)
            isEditingPIN = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            entryStep = .enter
        }
    }

    private func removePIN() async {
        guard !isRemoving else { return }
        isRemoving = true
        errorMessage = nil
        defer { isRemoving = false }

        do {
            try await service.removePIN(homeID: homeID)
            let updatedStatus = HomeAdminPinStatus(hasPIN: false, canManagePIN: true)
            status = updatedStatus
            onStatusChanged(updatedStatus)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProfileAvatarView: View {
    let profile: UserProfile?
    let size: CGFloat
    var isLoading = false

    var body: some View {
        AsyncImage(url: profile?.avatarURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Text(profile?.initials ?? "HM")
                    .font(.system(size: size * 0.31, weight: .bold))
                    .foregroundStyle(HomeyColors.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HomeyColors.primary.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(HomeyColors.primary.opacity(0.20), lineWidth: 1) }
        .overlay { if isLoading { ProgressView().tint(HomeyColors.primary) } }
        .accessibilityLabel("Profile photo for \(profile?.preferredDisplayName ?? "Homey Member")")
    }
}
