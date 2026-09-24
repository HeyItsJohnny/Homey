import SwiftUI

struct HomeMembersView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showingInvite = false
    @State private var invitationToCancel: HomeInvitationDisplay?
    @State private var statusMessage: String?
    @State private var actionError: String?

    private var home: HomeSummary? { session.activeHome }
    private var members: [HomeMemberDisplay] { session.homes.membersForSelectedHome() }
    private var invitations: [HomeInvitationDisplay] { session.homes.invitationsForSelectedHome() }
    private var canManageInvitations: Bool { session.activeRole?.canManageInvitations == true }

    var body: some View {
        ZStack {
            HomeyBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let home {
                        Text(home.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeyColors.secondaryText)
                    }
                    if let statusMessage { statusBanner(statusMessage) }
                    membersCard
                    if canManageInvitations { invitationsCard }
                }
                .padding(18)
            }
            .refreshable { await refresh() }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if canManageInvitations {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingInvite = true } label: { Image(systemName: "person.badge.plus") }
                        .disabled(session.homes.isCreatingInvitation)
                        .accessibilityLabel("Invite Member")
                }
            }
        }
        .task(id: home?.id) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .homeyMembersDidChange)) { notification in
            guard let home, notification.object == nil || notification.object as? UUID == home.id else { return }
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeyProfileDidChange)) { _ in
            Task { await refreshMembers() }
        }
        .sheet(isPresented: $showingInvite) {
            if let home {
                InviteHomeMemberSheet(home: home, members: members, pendingInvitations: invitations) {
                    statusMessage = "Invitation created."
                }
            }
        }
        .confirmationDialog(
            "Cancel Invitation?",
            isPresented: Binding(get: { invitationToCancel != nil }, set: { if !$0 { invitationToCancel = nil } }),
            titleVisibility: .visible,
            presenting: invitationToCancel
        ) { invitation in
            Button("Keep Invitation", role: .cancel) { invitationToCancel = nil }
            Button("Cancel Invitation", role: .destructive) { Task { await cancel(invitation) } }
        } message: { invitation in
            Text("The invitation for \(invitation.email) will no longer be available to accept.")
        }
        .alert("Members", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(actionError ?? "") }
    }

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Current Members", subtitle: "People with access to this Home")
            if let error = session.homes.membersErrorMessage, !members.isEmpty { HomeyErrorView(message: error) }

            if session.homes.isLoadingMembers && members.isEmpty {
                loadingRow("Loading members…")
            } else if let error = session.homes.membersErrorMessage, members.isEmpty {
                errorState(error) { await refreshMembers() }
            } else if members.isEmpty {
                emptyState("No Members Found", icon: "person.2", detail: "No visible members are available for this Home.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        NavigationLink {
                            HomeMemberDetailView(member: member, homeName: home?.name ?? "Home")
                        } label: {
                            HomeMemberRow(member: member)
                        }
                        .buttonStyle(.plain)
                        if index < members.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
            }
        }
        .homeyCard()
    }

    private var invitationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Pending Invitations", subtitle: "Invited people who have not joined yet")
            if let error = session.homes.invitationsErrorMessage, !invitations.isEmpty { HomeyErrorView(message: error) }

            if session.homes.isLoadingInvitations && invitations.isEmpty {
                loadingRow("Loading invitations…")
            } else if let error = session.homes.invitationsErrorMessage, invitations.isEmpty {
                errorState(error) { await refreshInvitations() }
            } else if invitations.isEmpty {
                Text("No pending invitations.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(invitations.enumerated()), id: \.element.id) { index, invitation in
                        invitationRow(invitation)
                        if index < invitations.count - 1 { Divider().padding(.leading, 54) }
                    }
                }
            }
        }
        .homeyCard()
    }

    private func invitationRow(_ invitation: HomeInvitationDisplay) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge")
                .foregroundStyle(HomeyColors.primary)
                .frame(width: 42, height: 42)
                .background(HomeyColors.primary.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.email).font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text).lineLimit(1)
                Text("\(invitation.role.displayName) · \(invitation.status.displayName) · \(invitation.invitedDateText)")
                    .font(.caption).foregroundStyle(HomeyColors.secondaryText).lineLimit(2)
            }
            Spacer(minLength: 6)
            Button(role: .destructive) { invitationToCancel = invitation } label: {
                if session.homes.cancellingInvitationID == invitation.id {
                    ProgressView().controlSize(.small).tint(HomeyColors.danger)
                } else {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .frame(width: 44, height: 44)
            .disabled(session.homes.cancellingInvitationID != nil)
            .accessibilityLabel("Cancel invitation for \(invitation.email)")
        }
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
            Text(subtitle).font(.caption).foregroundStyle(HomeyColors.secondaryText)
        }
    }

    private func loadingRow(_ title: String) -> some View {
        HStack(spacing: 10) { ProgressView(); Text(title).foregroundStyle(HomeyColors.secondaryText) }
            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 90)
    }

    private func errorState(_ message: String, retry: @escaping () async -> Void) -> some View {
        VStack(spacing: 12) {
            HomeyErrorView(message: message)
            Button("Try Again") { Task { await retry() } }.buttonStyle(.bordered).tint(HomeyColors.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private func emptyState(_ title: String, icon: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(HomeyColors.primary)
            Text(title).font(.headline).foregroundStyle(HomeyColors.text)
            Text(detail).font(.caption).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }

    private func statusBanner(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium)).foregroundStyle(HomeyColors.success)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(HomeyColors.success.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private func load() async {
        guard let home, let userID = session.currentUser?.id else { return }
        await session.homes.loadMembers(homeID: home.id, currentUserID: userID)
        if canManageInvitations { await session.homes.loadPendingInvitations(homeID: home.id) }
    }

    private func refresh() async {
        await refreshMembers()
        if canManageInvitations { await refreshInvitations() }
    }

    private func refreshMembers() async {
        guard let home, let userID = session.currentUser?.id else { return }
        await session.homes.loadMembers(homeID: home.id, currentUserID: userID, forceRefresh: true)
    }

    private func refreshInvitations() async {
        guard let home, canManageInvitations else { return }
        await session.homes.loadPendingInvitations(homeID: home.id, forceRefresh: true)
    }

    private func cancel(_ invitation: HomeInvitationDisplay) async {
        if await session.homes.cancelInvitation(invitation) {
            invitationToCancel = nil
            statusMessage = "Invitation cancelled."
        } else {
            actionError = session.homes.invitationsErrorMessage ?? "The invitation could not be cancelled."
        }
    }
}

private struct HomeMemberRow: View {
    let member: HomeMemberDisplay

    var body: some View {
        HStack(spacing: 12) {
            HomeMemberAvatar(member: member, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName).font(.headline).foregroundStyle(HomeyColors.text).lineLimit(1)
                Text(member.email ?? "Email unavailable").font(.caption).foregroundStyle(HomeyColors.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(member.role.displayName).font(.caption.weight(.semibold)).foregroundStyle(roleColor)
                .padding(.horizontal, 9).padding(.vertical, 6).background(roleColor.opacity(0.10), in: Capsule())
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private var roleColor: Color { member.role == .owner ? HomeyColors.primary : HomeyColors.secondaryText }
}

struct HomeMemberAvatar: View {
    let member: HomeMemberDisplay
    var size: CGFloat = 52

    var body: some View {
        AsyncImage(url: member.avatarURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Text(member.initials).font(.system(size: size * 0.31, weight: .bold)).foregroundStyle(accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(accent.opacity(0.13))
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay { Circle().stroke(accent.opacity(0.18)) }
        .accessibilityLabel("Avatar for \(member.displayName)")
    }

    private var accent: Color {
        switch member.role {
        case .owner: HomeyColors.primary
        case .admin: HomeyColors.success
        case .member: HomeyColors.recipeOrangeAccent
        }
    }
}

private struct HomeMemberDetailView: View {
    let member: HomeMemberDisplay
    let homeName: String

    var body: some View {
        ZStack {
            HomeyBackground()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        HomeMemberAvatar(member: member, size: 92)
                        HStack(spacing: 7) {
                            Text(member.displayName).font(HomeyTypography.title).foregroundStyle(HomeyColors.text)
                            if member.isCurrentUser { Text("You").font(.caption.bold()).foregroundStyle(HomeyColors.primary) }
                        }
                        Text(member.email ?? "Email unavailable").font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity).homeyCard()

                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("Home", value: homeName)
                        Divider()
                        LabeledContent("Role", value: member.role.displayName)
                        if let joinedDateText = member.joinedDateText {
                            Divider()
                            LabeledContent("Joined", value: joinedDateText)
                        }
                    }
                    .font(.subheadline).foregroundStyle(HomeyColors.text).homeyCard()
                }
                .padding(18)
            }
        }
        .navigationTitle("Member Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InviteHomeMemberSheet: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let home: HomeSummary
    let members: [HomeMemberDisplay]
    let pendingInvitations: [HomeInvitationDisplay]
    let onSuccess: () -> Void
    @State private var email = ""
    @State private var role = HomeMemberRole.member
    @State private var errorMessage: String?

    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var validationError: String? { validate(normalizedEmail) }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Email Address").font(.subheadline.weight(.semibold))
                            TextField("name@example.com", text: $email)
                                .keyboardType(.emailAddress).textContentType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().homeyTextField()
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Role").font(.subheadline.weight(.semibold))
                            Picker("Role", selection: $role) {
                                ForEach(HomeMemberRole.invitationOptions) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        if let errorMessage { HomeyErrorView(message: errorMessage) }
                        else if !normalizedEmail.isEmpty, let validationError { HomeyErrorView(message: validationError) }
                        Button { Task { await send() } } label: {
                            if session.homes.isCreatingInvitation {
                                HStack { ProgressView().tint(.white); Text("Sending Invite…") }
                            } else {
                                Text("Invite Member")
                            }
                        }
                        .buttonStyle(HomeyButtonStyle())
                        .disabled(validationError != nil || session.homes.isCreatingInvitation)
                        .opacity(validationError == nil && !session.homes.isCreatingInvitation ? 1 : 0.55)
                        Text("The invitation will be available when the recipient signs in with this email address.")
                            .font(.caption).foregroundStyle(HomeyColors.secondaryText)
                    }
                    .homeyCard().padding(18)
                }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(session.homes.isCreatingInvitation)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(session.homes.isCreatingInvitation) } }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        guard let validationError = validate(normalizedEmail) else {
            errorMessage = nil
            if await session.homes.createInvitation(homeID: home.id, email: normalizedEmail, role: role) {
                onSuccess()
                dismiss()
            } else {
                errorMessage = session.homes.invitationsErrorMessage ?? "The invitation could not be created."
            }
            return
        }
        errorMessage = validationError
    }

    private func validate(_ email: String) -> String? {
        guard !email.isEmpty else { return "Enter a valid email address." }
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        guard email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else { return "Enter a valid email address." }
        if email == session.currentUser?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() { return "You cannot invite your own account." }
        if members.contains(where: { $0.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email }) { return "This person is already a member of this Home." }
        if pendingInvitations.contains(where: { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email && $0.status == .pending }) { return "An invitation is already pending for this email." }
        return nil
    }
}
