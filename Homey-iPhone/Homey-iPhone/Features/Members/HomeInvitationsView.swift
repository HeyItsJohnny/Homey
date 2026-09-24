import SwiftUI

struct HomeInvitationsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var invitationToDecline: HomeInvitationDisplay?
    @State private var acceptedInvitation: AcceptedHomeInvitationResult?
    @State private var errorMessage: String?

    private var invitations: [HomeInvitationDisplay] { session.homes.myPendingInvitations }

    var body: some View {
        ZStack {
            HomeyBackground()
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let error = session.homes.myInvitationsErrorMessage, !invitations.isEmpty {
                        HomeyErrorView(message: error).homeyCard()
                    }
                    if session.homes.isLoadingMyInvitations && invitations.isEmpty {
                        HStack(spacing: 10) { ProgressView(); Text("Loading invitations…") }
                            .foregroundStyle(HomeyColors.secondaryText).frame(maxWidth: .infinity, minHeight: 150).homeyCard()
                    } else if let error = session.homes.myInvitationsErrorMessage, invitations.isEmpty {
                        VStack(spacing: 12) {
                            HomeyErrorView(message: error)
                            Button("Try Again") { Task { await refresh() } }.buttonStyle(.bordered).tint(HomeyColors.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150).homeyCard()
                    } else if invitations.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "envelope.open").font(.largeTitle).foregroundStyle(HomeyColors.primary)
                            Text("No Pending Invitations").font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
                            Text("Invitations to join another Home will appear here.")
                                .font(.subheadline).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 190).homeyCard()
                    } else {
                        ForEach(invitations) { invitation in invitationCard(invitation) }
                    }
                }
                .padding(18)
            }
            .refreshable { await refresh() }
        }
        .navigationTitle("Home Invitations")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.currentUser?.id) { await load() }
        .confirmationDialog(
            "Decline Invitation?",
            isPresented: Binding(get: { invitationToDecline != nil }, set: { if !$0 { invitationToDecline = nil } }),
            titleVisibility: .visible,
            presenting: invitationToDecline
        ) { invitation in
            Button("Keep Invitation", role: .cancel) { invitationToDecline = nil }
            Button("Decline Invitation", role: .destructive) { Task { await decline(invitation) } }
        } message: { invitation in
            Text("You will not be added to \(invitation.homeName ?? "this Home").")
        }
        .confirmationDialog(
            "Welcome to \(acceptedInvitation?.homeName ?? "Home")",
            isPresented: Binding(get: { acceptedInvitation != nil }, set: { if !$0 { acceptedInvitation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Not Now", role: .cancel) { acceptedInvitation = nil }
            Button("Switch Home") { Task { await switchToAcceptedHome() } }
        } message: {
            Text("You are now a member of this Home. Would you like to switch to it now?")
        }
        .alert("Home Invitation Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func invitationCard(_ invitation: HomeInvitationDisplay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "house.fill").font(.title3).foregroundStyle(HomeyColors.primary)
                    .frame(width: 48, height: 48).background(HomeyColors.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.homeName ?? "A Homey Home").font(HomeyTypography.title).foregroundStyle(HomeyColors.text)
                    Text(inviterText(invitation)).font(.caption).foregroundStyle(HomeyColors.secondaryText)
                }
                Spacer(minLength: 6)
                Text(invitation.role.displayName).font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.primary)
                    .padding(.horizontal, 9).padding(.vertical, 6).background(HomeyColors.primary.opacity(0.10), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.invitedDateText)
                if let expirationText = invitation.expirationText { Text(expirationText) }
            }
            .font(.caption).foregroundStyle(HomeyColors.secondaryText)

            HStack(spacing: 10) {
                Button(role: .destructive) { invitationToDecline = invitation } label: {
                    if session.homes.decliningInvitationID == invitation.id { ProgressView().tint(HomeyColors.danger) }
                    else { Text("Decline") }
                }
                .buttonStyle(HomeyButtonStyle(secondary: true))
                .disabled(isBusy)

                Button { Task { await accept(invitation) } } label: {
                    if session.homes.acceptingInvitationID == invitation.id { ProgressView().tint(.white) }
                    else { Text("Accept Invitation") }
                }
                .buttonStyle(HomeyButtonStyle())
                .disabled(isBusy)
            }
        }
        .homeyCard()
    }

    private var isBusy: Bool {
        session.homes.acceptingInvitationID != nil || session.homes.decliningInvitationID != nil
    }

    private func inviterText(_ invitation: HomeInvitationDisplay) -> String {
        guard let name = invitation.inviterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "You have been invited to join this Home."
        }
        return "\(name) invited you to join this Home."
    }

    private func load() async {
        guard let userID = session.currentUser?.id else { return }
        await session.homes.loadMyPendingInvitations(userID: userID)
    }

    private func refresh() async {
        guard let userID = session.currentUser?.id else { return }
        await session.homes.loadMyPendingInvitations(userID: userID, forceRefresh: true)
    }

    private func accept(_ invitation: HomeInvitationDisplay) async {
        guard let userID = session.currentUser?.id else { errorMessage = "Please sign in and try again."; return }
        let hadActiveHome = session.activeHome != nil
        guard let result = await session.homes.acceptInvitation(invitation, currentUserID: userID) else {
            errorMessage = session.homes.myInvitationsErrorMessage ?? "We couldn't accept this invitation."
            return
        }
        if hadActiveHome {
            acceptedInvitation = result
        } else {
            await selectAcceptedHome(result)
        }
    }

    private func decline(_ invitation: HomeInvitationDisplay) async {
        guard let userID = session.currentUser?.id else { errorMessage = "Please sign in and try again."; return }
        if await session.homes.declineInvitation(invitation, currentUserID: userID) {
            invitationToDecline = nil
        } else {
            errorMessage = session.homes.myInvitationsErrorMessage ?? "We couldn't decline this invitation."
        }
    }

    private func switchToAcceptedHome() async {
        guard let acceptedInvitation else { return }
        await selectAcceptedHome(acceptedInvitation)
    }

    private func selectAcceptedHome(_ result: AcceptedHomeInvitationResult) async {
        guard let home = session.homes.homes.first(where: { $0.id == result.homeID }) else {
            errorMessage = "The Home was joined, but it could not be selected yet. Refresh and try again."
            return
        }
        acceptedInvitation = nil
        if await session.switchHome(to: home) {
            dismiss()
        } else {
            errorMessage = session.homeSwitchErrorMessage ?? "The Home was joined, but it could not be selected."
        }
    }
}
