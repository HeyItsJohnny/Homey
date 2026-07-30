import SwiftUI

struct HomeMembersView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService

    var onClose: () -> Void = {}

    @State private var isShowingInviteSheet = false
    @State private var successMessage: String?
    @State private var invitationToCancel: HomeInvitationDisplay?
    @State private var isShowingCancelConfirmation = false
    @State private var cancelErrorMessage: String?
    @State private var isShowingCancelError = false

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var members: [HomeMemberDisplay] {
        homeService.membersForSelectedHome()
    }

    private var pendingInvitations: [HomeInvitationDisplay] {
        homeService.invitationsForSelectedHome()
    }

    private var memberCountText: String {
        let count = homeService.memberCountForSelectedHome() ?? selectedHome?.memberCount ?? members.count
        return "\(count) \(count == 1 ? "Member" : "Members")"
    }

    private var hasLoadedMembers: Bool {
        homeService.hasLoadedMembersForSelectedHome()
    }

    private var hasLoadedInvitations: Bool {
        homeService.hasLoadedInvitationsForSelectedHome()
    }

    private var canManageInvitations: Bool {
        guard let role = selectedHome?.role?.lowercased() else {
            return false
        }

        return role == "owner" || role == "admin"
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if let successMessage {
                        MembersStatusBanner(message: successMessage)
                            .transition(.opacity)
                    }

                    if selectedHome == nil {
                        missingHomeState
                    } else {
                        membersCard
                        pendingInvitationsSection
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshAllData()
            }
        }
        .task(id: selectedHome?.id) {
            await loadDataIfNeeded()
        }
        .sheet(isPresented: $isShowingInviteSheet) {
            InviteMemberSheet(
                selectedHome: selectedHome,
                members: members,
                pendingInvitations: pendingInvitations
            ) { message in
                withAnimation(.easeInOut(duration: 0.2)) {
                    successMessage = message
                }
            }
            .environmentObject(authenticationService)
            .environmentObject(homeService)
        }
        .confirmationDialog(
            "Cancel Invitation?",
            isPresented: $isShowingCancelConfirmation,
            titleVisibility: .visible,
            presenting: invitationToCancel
        ) { invitation in
            Button("Keep Invitation", role: .cancel) {
                invitationToCancel = nil
            }
            Button("Cancel Invitation", role: .destructive) {
                Task {
                    await cancelInvitation(invitation)
                }
            }
        } message: { _ in
            Text("This invitation will no longer be available to accept.")
        }
        .alert("Unable to Cancel Invitation", isPresented: $isShowingCancelError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancelErrorMessage ?? "Please try again.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Members")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    if selectedHome != nil && hasLoadedMembers && !homeService.isLoadingMembers {
                        Text(memberCountText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                    }
                }

                Text("Everyone currently connected to this home.")
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            if canManageInvitations {
                Button {
                    successMessage = nil
                    isShowingInviteSheet = true
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "person.badge.plus")
                        Text("Invite Member")
                    }
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 190)
                .disabled(homeService.isCreatingInvitation)
                .accessibilityLabel("Invite Member")
            }

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

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                title: "Current Members",
                subtitle: "People with access to this home."
            )

            VStack(alignment: .leading, spacing: 0) {
                if (homeService.isLoadingMembers || !hasLoadedMembers) && members.isEmpty && homeService.membersErrorMessage == nil {
                    loadingState(title: "Loading members...", accessibilityLabel: "Loading members")
                } else if let errorMessage = homeService.membersErrorMessage, members.isEmpty {
                    membersErrorState(message: errorMessage)
                } else if members.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        HomeMemberRow(member: member)

                        if index < members.count - 1 {
                            Divider()
                                .background(HomeyDashboardTheme.softBorder)
                                .padding(.leading, 76)
                        }
                    }
                }
            }
        }
        .padding(24)
        .dashboardCard(cornerRadius: 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Members list")
    }

    private var pendingInvitationsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                title: "Pending Invitations",
                subtitle: "People who have been invited but have not joined yet."
            )

            VStack(alignment: .leading, spacing: 0) {
                if (homeService.isLoadingInvitations || !hasLoadedInvitations) && pendingInvitations.isEmpty && homeService.invitationsErrorMessage == nil {
                    loadingState(title: "Loading invitations...", accessibilityLabel: "Loading pending invitations")
                } else if let errorMessage = homeService.invitationsErrorMessage, pendingInvitations.isEmpty {
                    invitationsErrorState(message: errorMessage)
                } else if pendingInvitations.isEmpty {
                    subtleEmptyInvitationState
                } else {
                    ForEach(Array(pendingInvitations.enumerated()), id: \.element.id) { index, invitation in
                        PendingInvitationRow(
                            invitation: invitation,
                            canCancel: canManageInvitations,
                            isCancelling: homeService.cancellingInvitationID == invitation.id
                        ) {
                            invitationToCancel = invitation
                            isShowingCancelConfirmation = true
                        }

                        if index < pendingInvitations.count - 1 {
                            Divider()
                                .background(HomeyDashboardTheme.softBorder)
                                .padding(.leading, 58)
                        }
                    }
                }
            }
        }
        .padding(24)
        .dashboardCard(cornerRadius: 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pending invitations")
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

    private func loadingState(title: String, accessibilityLabel: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(HomeyDashboardTheme.warmBrown)
                .accessibilityLabel(accessibilityLabel)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)

            Text("No Members Found")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text("This home does not have any visible members yet.")
                .font(.body)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .accessibilityElement(children: .combine)
    }

    private var subtleEmptyInvitationState: some View {
        Text("No pending invitations.")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
            .accessibilityLabel("No pending invitations")
    }

    private func membersErrorState(message: String) -> some View {
        errorState(
            title: "Unable to Load Members",
            message: message,
            isLoading: homeService.isLoadingMembers,
            retryAction: refreshAllData
        )
    }

    private func invitationsErrorState(message: String) -> some View {
        errorState(
            title: "Unable to Load Invitations",
            message: message,
            isLoading: homeService.isLoadingInvitations,
            retryAction: refreshInvitations
        )
    }

    private func errorState(title: String, message: String, isLoading: Bool, retryAction: @escaping () async -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(HomeyDashboardTheme.destructiveRed)

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text(message)
                .font(.body)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await retryAction()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Try Again")
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isLoading)
            .accessibilityLabel("Try Again")
            .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .accessibilityElement(children: .contain)
    }

    private var missingHomeState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unable to Load Members")
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

    // MARK: - Loading

    private func loadDataIfNeeded() async {
        guard let selectedHome, let currentUser = authenticationService.currentUser else {
            return
        }

        await homeService.loadMembers(for: selectedHome.id, currentUser: currentUser)
        await homeService.loadPendingInvitations(for: selectedHome.id)
    }

    private func refreshAllData() async {
        guard let selectedHome, let currentUser = authenticationService.currentUser else {
            return
        }

        await homeService.refreshMembers(for: selectedHome.id, currentUser: currentUser)
        await homeService.refreshPendingInvitations(for: selectedHome.id)
    }

    private func refreshInvitations() async {
        guard let selectedHome else {
            return
        }

        await homeService.refreshPendingInvitations(for: selectedHome.id)
    }

    private func cancelInvitation(_ invitation: HomeInvitationDisplay) async {
        let didCancel = await homeService.cancelInvitation(invitation)

        if didCancel {
            invitationToCancel = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                successMessage = "Invitation Cancelled"
            }
        } else {
            cancelErrorMessage = homeService.invitationsErrorMessage ?? "Please try again."
            isShowingCancelError = true
        }
    }
}

struct HomeMemberRow: View {
    let member: HomeMemberDisplay

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            MemberAvatarView(member: member, size: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(member.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(1)

                    if member.isCurrentUser {
                        Text("You")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                            .accessibilityLabel("You")
                    }
                }

                Text(member.email ?? "Email unavailable")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 18)

            RoleBadge(role: member.formattedRole, rawRole: member.role)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let emailText = member.email ?? "Email unavailable"
        let currentUserText = member.isCurrentUser ? ", You" : ""
        return "\(member.displayName), \(emailText), \(member.formattedRole)\(currentUserText)"
    }
}

struct MemberAvatarView: View {
    let member: HomeMemberDisplay
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor.opacity(0.24))

            if let avatarURL = member.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .tint(HomeyDashboardTheme.warmBrown)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
                .clipShape(Circle())
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Circle()
                .stroke(HomeyDashboardTheme.cardBackground, lineWidth: 3)
        }
        .accessibilityLabel("Avatar for \(member.displayName)")
    }

    private var initialsView: some View {
        Text(member.initials)
            .font(.system(size: max(12, size * 0.34), weight: .bold, design: .rounded))
            .foregroundStyle(avatarColor)
    }

    private var avatarColor: Color {
        switch member.role.lowercased() {
        case "owner":
            return HomeyDashboardTheme.warmBrown
        case "admin":
            return HomeyDashboardTheme.sageAccent
        default:
            return HomeyDashboardTheme.orangeAccent
        }
    }
}

struct DashboardMemberAvatarStack: View {
    let members: [HomeMemberDisplay]
    var avatarSize: CGFloat = 38

    private var visibleMembers: [HomeMemberDisplay] {
        Array(members.prefix(4))
    }

    private var remainingCount: Int {
        max(0, members.count - visibleMembers.count)
    }

    var body: some View {
        HStack(spacing: -8) {
            ForEach(visibleMembers) { member in
                MemberAvatarView(member: member, size: avatarSize)
            }

            if remainingCount > 0 {
                Text("+\(remainingCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(HomeyDashboardTheme.cardBackground, lineWidth: 3)
                    }
                    .accessibilityLabel("\(remainingCount) more members")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PendingInvitationRow: View {
    let invitation: HomeInvitationDisplay
    let canCancel: Bool
    let isCancelling: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(HomeyDashboardTheme.selectedSidebarBackground)

                Image(systemName: "envelope.badge")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(invitation.email)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(1)

                Text("\(invitation.formattedRole) · \(invitation.invitedDateText)")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 18)

            Text(invitation.formattedStatus)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                .accessibilityLabel("Status: \(invitation.formattedStatus)")

            if canCancel {
                Button(action: onCancel) {
                    if isCancelling {
                        ProgressView()
                            .controlSize(.small)
                            .tint(HomeyDashboardTheme.destructiveRed)
                    } else {
                        Text("Cancel")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                .frame(minWidth: 70, minHeight: 44)
                .disabled(isCancelling)
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel invitation for \(invitation.email)")
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Invitation for \(invitation.email), \(invitation.formattedRole), \(invitation.formattedStatus), \(invitation.invitedDateText)")
    }
}

private struct InviteMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService

    let selectedHome: HomeSummary?
    let members: [HomeMemberDisplay]
    let pendingInvitations: [HomeInvitationDisplay]
    let onSuccess: (String) -> Void

    @State private var email = ""
    @State private var selectedRole = InviteRole.member
    @State private var validationMessage: String?
    @State private var createErrorMessage: String?
    @State private var isShowingCreateError = false

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canCreate: Bool {
        !homeService.isCreatingInvitation && validationMessage(for: normalizedEmail) == nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Invite Member")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(HomeyDashboardTheme.primaryText)

                            Text("Invite someone to join this home.")
                                .font(.title3)
                                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 9) {
                                settingsLabel("Email Address", supportingText: "Use the email address they will use for Homey.")

                                HStack(spacing: 12) {
                                    Image(systemName: "envelope")
                                        .foregroundStyle(HomeyDashboardTheme.secondaryText)

                                    TextField("Email Address", text: $email)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .keyboardType(.emailAddress)
                                        .textContentType(.emailAddress)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                                        .onChange(of: email) { _, newValue in
                                            validationMessage = validationMessage(for: newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                                        }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 56)
                                .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                                }
                                .accessibilityLabel("Email Address")
                            }

                            VStack(alignment: .leading, spacing: 9) {
                                settingsLabel("Role", supportingText: "Choose what this person can manage in the home.")

                                Picker("Role", selection: $selectedRole) {
                                    ForEach(InviteRole.allCases) { role in
                                        Text(role.title).tag(role)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .accessibilityLabel("Invitation Role")
                            }

                            if let validationMessage {
                                MembersErrorBanner(message: validationMessage)
                            }

                            MembersStatusBanner(
                                message: "Creating an invitation record only. Email delivery will be added later."
                            )

                            Button {
                                Task {
                                    await createInvitation()
                                }
                            } label: {
                                if homeService.isCreatingInvitation {
                                    ProgressView()
                                        .tint(.white)
                                        .accessibilityLabel("Creating invitation")
                                } else {
                                    Text("Create Invitation")
                                }
                            }
                            .buttonStyle(DashboardPrimaryButtonStyle())
                            .disabled(!canCreate)
                            .accessibilityLabel("Create Invitation")
                        }
                        .padding(28)
                        .dashboardCard(cornerRadius: 30)
                    }
                    .padding(34)
                    .frame(maxWidth: 620, alignment: .leading)
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
                    .disabled(homeService.isCreatingInvitation)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Unable to Create Invitation", isPresented: $isShowingCreateError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(createErrorMessage ?? "Please try again.")
        }
    }

    private func createInvitation() async {
        let validation = validationMessage(for: normalizedEmail)
        validationMessage = validation

        guard validation == nil else {
            return
        }

        guard let selectedHome else {
            createErrorMessage = "Please choose a Home and try again."
            isShowingCreateError = true
            return
        }

        guard let currentUser = authenticationService.currentUser else {
            createErrorMessage = "Please sign in and try again."
            isShowingCreateError = true
            return
        }

        let didCreate = await homeService.createInvitation(
            homeID: selectedHome.id,
            email: normalizedEmail,
            role: selectedRole.rawValue,
            invitedBy: currentUser.id
        )

        if didCreate {
            email = ""
            selectedRole = .member
            onSuccess("Invitation Created\nThe invitation has been added to this home.")
            dismiss()
        } else {
            createErrorMessage = homeService.invitationsErrorMessage ?? "The invitation could not be created. Please try again."
            isShowingCreateError = true
        }
    }

    private func validationMessage(for email: String) -> String? {
        guard !email.isEmpty else {
            return "Enter a valid email address."
        }

        guard isValidEmail(email) else {
            return "Enter a valid email address."
        }

        if let currentUser = authenticationService.currentUser,
           email == currentUser.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return "You cannot invite your own account."
        }

        if members.contains(where: { member in
            member.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email
        }) {
            return "This person is already a member of this home."
        }

        if pendingInvitations.contains(where: { invitation in
            invitation.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email && invitation.status.lowercased() == "pending"
        }) {
            return "An invitation is already pending for this email."
        }

        return nil
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private enum InviteRole: String, CaseIterable, Identifiable {
    case member
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .member:
            return "Member"
        case .admin:
            return "Admin"
        }
    }
}

private struct RoleBadge: View {
    let role: String
    let rawRole: String

    var body: some View {
        Text(role)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel("Role: \(role)")
    }

    private var foregroundColor: Color {
        rawRole.lowercased() == "owner" ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText
    }

    private var backgroundColor: Color {
        rawRole.lowercased() == "owner" ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.appBackground.opacity(0.72)
    }
}

private struct MembersStatusBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HomeyDashboardTheme.sageAccent)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.sageAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(message)
    }
}

private struct MembersErrorBanner: View {
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

private func settingsLabel(_ title: String, supportingText: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.primaryText)

        Text(supportingText)
            .font(.subheadline)
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
    }
}

#Preview("Home Members Row") {
    HomeMemberRow(member: HomeMembersPreviewData.members[0])
        .padding()
        .background(HomeyDashboardTheme.appBackground)
}

#Preview("Pending Invitation Row") {
    PendingInvitationRow(
        invitation: HomeMembersPreviewData.invitations[0],
        canCancel: true,
        isCancelling: false,
        onCancel: {}
    )
    .padding()
    .background(HomeyDashboardTheme.appBackground)
}

#Preview("Home Members List") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(HomeMembersPreviewData.members) { member in
                    HomeMemberRow(member: member)
                    Divider()
                        .padding(.leading, 76)
                }
            }
            .padding(24)
            .dashboardCard(cornerRadius: 30)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(HomeMembersPreviewData.invitations) { invitation in
                    PendingInvitationRow(
                        invitation: invitation,
                        canCancel: true,
                        isCancelling: false,
                        onCancel: {}
                    )
                    Divider()
                        .padding(.leading, 58)
                }
            }
            .padding(24)
            .dashboardCard(cornerRadius: 30)
        }
        .padding(34)
    }
    .background(HomeyDashboardTheme.appBackground)
}

#Preview("Dashboard Member Avatars") {
    DashboardMemberAvatarStack(members: HomeMembersPreviewData.members, avatarSize: 44)
        .padding()
        .background(HomeyDashboardTheme.cardBackground)
}

private enum HomeMembersPreviewData {
    static let members = [
        HomeMemberDisplay(
            id: UUID(),
            userId: UUID(),
            displayName: "Johnny Laroco",
            email: "johnny@example.com",
            role: "owner",
            avatarURL: nil,
            isCurrentUser: true
        ),
        HomeMemberDisplay(
            id: UUID(),
            userId: UUID(),
            displayName: "Sarah Laroco",
            email: "sarah@example.com",
            role: "admin",
            avatarURL: nil,
            isCurrentUser: false
        ),
        HomeMemberDisplay(
            id: UUID(),
            userId: UUID(),
            displayName: "Mia Laroco",
            email: "mia@example.com",
            role: "member",
            avatarURL: nil,
            isCurrentUser: false
        ),
        HomeMemberDisplay(
            id: UUID(),
            userId: UUID(),
            displayName: "Leo Laroco",
            email: nil,
            role: "member",
            avatarURL: nil,
            isCurrentUser: false
        ),
        HomeMemberDisplay(
            id: UUID(),
            userId: UUID(),
            displayName: "Nora Laroco",
            email: "nora@example.com",
            role: "member",
            avatarURL: nil,
            isCurrentUser: false
        )
    ]

    static let invitations = [
        HomeInvitationDisplay(
            id: UUID(),
            homeID: UUID(),
            email: "alex@example.com",
            role: "member",
            status: "pending",
            invitedBy: UUID(),
            createdAt: "2026-07-26T12:00:00Z",
            expiresAt: nil
        ),
        HomeInvitationDisplay(
            id: UUID(),
            homeID: UUID(),
            email: "taylor@example.com",
            role: "admin",
            status: "pending",
            invitedBy: UUID(),
            createdAt: "2026-07-25T12:00:00Z",
            expiresAt: nil
        )
    ]
}
