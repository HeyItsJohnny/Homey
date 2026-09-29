import SwiftUI

struct AccountResolutionView: View {
    @EnvironmentObject private var appSession: AppSession
    let errorMessage: String?

    var body: some View {
        ZStack {
            HomeyBackground()
            VStack(spacing: 18) {
                Image(systemName: errorMessage == nil ? "house.and.flag.fill" : "wifi.exclamationmark")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(HomeyColors.primary)

                if let errorMessage {
                    Text("Homey Couldn't Finish Setup")
                        .font(HomeyTypography.title)
                        .foregroundStyle(HomeyColors.text)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(HomeyColors.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await appSession.retryAccountResolution() }
                    }
                    .buttonStyle(HomeyButtonStyle())
                    Button("Sign Out") { Task { await appSession.signOut() } }
                        .buttonStyle(HomeyButtonStyle(secondary: true))
                } else {
                    ProgressView().controlSize(.large).tint(HomeyColors.primary)
                    Text("Resolving Homey account…")
                        .font(HomeyTypography.title)
                        .foregroundStyle(HomeyColors.text)
                    Text("Checking your Homes and invitations.")
                        .font(.subheadline)
                        .foregroundStyle(HomeyColors.secondaryText)
                }
            }
            .padding(28)
            .frame(maxWidth: 390)
            .homeyCard()
            .padding(20)
        }
    }
}

struct PendingInvitationsOnboardingView: View {
    @EnvironmentObject private var appSession: AppSession
    @State private var actionError: String?

    private var invitations: [HomeInvitationDisplay] { appSession.homes.myPendingInvitations }
    private var isBusy: Bool { appSession.homes.acceptingInvitationID != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        HomeyBrandHeader(
                            title: "Welcome to Homey",
                            subtitle: invitations.count == 1
                                ? "You've been invited to join a Home."
                                : "You've been invited to join Homes."
                        )

                        if invitations.isEmpty, isBusy {
                            HStack(spacing: 12) {
                                ProgressView().tint(HomeyColors.primary)
                                Text("Finishing your Home setup…")
                                    .foregroundStyle(HomeyColors.secondaryText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .homeyCard()
                        } else {
                            ForEach(invitations) { invitation in
                                invitationCard(invitation)
                            }
                        }

                        if let error = actionError ?? appSession.accountResolutionErrorMessage {
                            HomeyErrorView(message: error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button("Create My Own Home") {
                            appSession.createOwnHomeFromInvitations()
                        }
                        .buttonStyle(HomeyButtonStyle(secondary: true))
                        .disabled(isBusy)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { Task { await appSession.signOut() } }
                        .disabled(isBusy)
                }
            }
        }
    }

    private func invitationCard(_ invitation: HomeInvitationDisplay) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "house.fill")
                    .font(.title2)
                    .foregroundStyle(HomeyColors.primary)
                    .frame(width: 52, height: 52)
                    .background(HomeyColors.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 5) {
                    Text(invitation.homeName ?? "A Homey Home")
                        .font(HomeyTypography.title)
                        .foregroundStyle(HomeyColors.text)
                    if let inviter = invitation.inviterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !inviter.isEmpty {
                        Text("Invited by \(inviter)")
                            .font(.subheadline)
                            .foregroundStyle(HomeyColors.secondaryText)
                    }
                    Text("Role: \(invitation.role.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(HomeyColors.secondaryText)
                }
                Spacer(minLength: 0)
            }

            Button {
                Task { await join(invitation) }
            } label: {
                HStack {
                    if appSession.homes.acceptingInvitationID == invitation.id {
                        ProgressView().tint(.white)
                    }
                    Text("Join Home")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(HomeyButtonStyle())
            .disabled(isBusy)
        }
        .homeyCard()
    }

    private func join(_ invitation: HomeInvitationDisplay) async {
        actionError = nil
        if !(await appSession.joinHomeFromOnboarding(invitation)) {
            actionError = appSession.accountResolutionErrorMessage
                ?? appSession.homeSwitchErrorMessage
                ?? "We couldn't join this Home. Please try again."
        }
    }
}

struct CreateHomeView: View {
    @EnvironmentObject private var appSession: AppSession
    @State private var name = ""
    @State private var timezone = TimeZone.current.identifier

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                ScrollView {
                    VStack(spacing: 22) {
                        HomeyBrandHeader(title: "Create Home", subtitle: "Create your family's Home to get organized together.")
                        TextField("Home name", text: $name).textInputAutocapitalization(.words).submitLabel(.done).homeyTextField()
                        Picker("Timezone", selection: $timezone) {
                            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.navigationLink).homeyTextField()
                        if let error = appSession.homes.errorMessage { HomeyErrorView(message: error) }
                        Button(action: create) {
                            if appSession.homes.isLoading { ProgressView().tint(.white) } else { Text("Create Home") }
                        }.buttonStyle(HomeyButtonStyle()).disabled(appSession.homes.isLoading)
                        NavigationLink("View Invites") { HomeInvitationsView() }
                            .buttonStyle(HomeyButtonStyle(secondary: true))
                    }.homeyCard().padding(.horizontal, 20).padding(.vertical, 28)
                }.scrollDismissesKeyboard(.interactively)
            }.toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { HomeInvitationsView() } label: { Image(systemName: "envelope.badge") }
                        .accessibilityLabel("Invites")
                    Button("Sign Out") { Task { await appSession.signOut() } }
                }
            }
        }
    }

    private func create() {
        guard let userID = appSession.currentUser?.id else { return }
        Task { if await appSession.homes.createHome(name: name, timezone: timezone, userID: userID) { appSession.homeWasCreated() } }
    }
}

struct HomeSelectionView: View {
    @EnvironmentObject private var appSession: AppSession
    @State private var showingCreateHome = false

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        header

                        if let error = appSession.homeSwitchErrorMessage ?? appSession.homes.errorMessage {
                            HomeyErrorView(message: error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .homeyCard()
                        }

                        if appSession.homes.isLoading && appSession.homes.homes.isEmpty {
                            loadingState
                        } else if appSession.homes.homes.isEmpty {
                            emptyState
                        } else {
                            if let current = appSession.activeHome {
                                sectionTitle("Current Home", subtitle: "The household currently shown in Homey")
                                HomeChoiceCard(home: current, isCurrent: true, isSwitching: false) {}
                                    .disabled(true)
                            }

                            sectionTitle("Your Homes", subtitle: "Choose a household to view and manage")
                            ForEach(appSession.homes.homes) { home in
                                let isCurrent = home.id == appSession.activeHome?.id
                                HomeChoiceCard(
                                    home: home,
                                    isCurrent: isCurrent,
                                    isSwitching: appSession.switchingHomeID == home.id
                                ) {
                                    Task { await appSession.switchHome(to: home) }
                                }
                                .disabled(appSession.isSwitchingHome || appSession.homes.isLoading)
                            }

                            sectionTitle("More Options", subtitle: "Add another household space")
                            Button { showingCreateHome = true } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "plus")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(HomeyColors.primary)
                                        .frame(width: 46, height: 46)
                                        .background(HomeyColors.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Create Another Home").font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
                                        Text("Start a separate household space.").font(.caption).foregroundStyle(HomeyColors.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                                }
                                .homeyCard()
                            }
                            .buttonStyle(.plain)
                            .disabled(appSession.isSwitchingHome)
                        }
                    }
                    .padding(18)
                }
                .refreshable { await appSession.refreshHomeChoices() }
            }
            .navigationTitle(appSession.activeHome == nil ? "Choose a Home" : "Change Home")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(appSession.isSwitchingHome)
            .toolbar {
                if appSession.activeHome != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { appSession.cancelHomeSelection() }
                            .disabled(appSession.isSwitchingHome)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { HomeInvitationsView() } label: { Image(systemName: "envelope.badge") }
                        .accessibilityLabel("Invites")
                        .disabled(appSession.isSwitchingHome)
                    Button("Sign Out") { Task { await appSession.signOut() } }
                        .disabled(appSession.isSwitchingHome)
                }
            }
            .task { await appSession.refreshHomeChoices() }
            .sheet(isPresented: $showingCreateHome) { CreateHomeView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(appSession.activeHome == nil ? "Choose a Home" : "Change Home")
                .font(HomeyTypography.hero)
                .foregroundStyle(HomeyColors.text)
            Text("Choose which Home you want to view and manage.")
                .font(.body)
                .foregroundStyle(HomeyColors.secondaryText)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView().tint(HomeyColors.primary)
            Text("Loading your Homes…").foregroundStyle(HomeyColors.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .homeyCard()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "house").font(.system(size: 34, weight: .semibold)).foregroundStyle(HomeyColors.primary)
            Text("No Homes Available").font(HomeyTypography.title).foregroundStyle(HomeyColors.text)
            Text("Create a Home or accept an invitation to get started.")
                .font(.subheadline).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.center)
            Button("Create Home") { showingCreateHome = true }.buttonStyle(HomeyButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .homeyCard()
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
            Text(subtitle).font(.caption).foregroundStyle(HomeyColors.secondaryText)
        }
    }
}

private struct HomeChoiceCard: View {
    let home: HomeSummary
    let isCurrent: Bool
    let isSwitching: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: "house.fill")
                    .font(.headline)
                    .foregroundStyle(HomeyColors.primary)
                    .frame(width: 50, height: 50)
                    .background(HomeyColors.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(home.name).font(HomeyTypography.headline).foregroundStyle(HomeyColors.text).lineLimit(1)
                        if isCurrent {
                            Text("Current")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(HomeyColors.primary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(HomeyColors.primary.opacity(0.10), in: Capsule())
                        }
                    }
                    Text(home.role?.displayName ?? "Role unavailable")
                        .font(.subheadline)
                        .foregroundStyle(HomeyColors.secondaryText)
                }

                Spacer(minLength: 8)
                if isSwitching {
                    ProgressView().tint(HomeyColors.primary)
                } else if isCurrent {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(HomeyColors.primary)
                } else {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            .homeyCard()
            .overlay {
                RoundedRectangle(cornerRadius: HomeyCornerRadius.card)
                    .stroke(isCurrent ? HomeyColors.primary.opacity(0.25) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrent ? "Current Home, \(home.name), \(home.role?.displayName ?? "role unavailable")" : "Switch to \(home.name), \(home.role?.displayName ?? "role unavailable")")
    }
}
