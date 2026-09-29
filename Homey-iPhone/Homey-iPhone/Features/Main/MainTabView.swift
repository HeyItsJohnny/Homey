import SwiftUI

private enum MainTab: Hashable { case home, calendar, meals, chores, groceries }

struct MainTabView: View {
    @State private var selection: MainTab = .home
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView(navigate: navigate) }.tabItem { Label("Home", systemImage: "house.fill") }.tag(MainTab.home)
            tab("Calendar", "calendar").tabItem { Label("Calendar", systemImage: "calendar") }.tag(MainTab.calendar)
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
            .sheet(isPresented: $showingEditor) {
                EditProfileView { message in
                    statusMessage = message
                    profileError = nil
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
