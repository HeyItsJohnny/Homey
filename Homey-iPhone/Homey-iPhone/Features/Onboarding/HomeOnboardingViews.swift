import SwiftUI

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
                    }.homeyCard().padding(.horizontal, 20).padding(.vertical, 28)
                }.scrollDismissesKeyboard(.interactively)
            }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sign Out") { Task { await appSession.signOut() } } } }
        }
    }

    private func create() {
        guard let userID = appSession.currentUser?.id else { return }
        Task { if await appSession.homes.createHome(name: name, timezone: timezone, userID: userID) { appSession.homeWasCreated() } }
    }
}

struct HomeSelectionView: View {
    @EnvironmentObject private var appSession: AppSession
    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Choose a Home").font(HomeyTypography.hero).foregroundStyle(HomeyColors.text)
                        Text("Select where you'd like to start.").foregroundStyle(HomeyColors.secondaryText)
                        ForEach(appSession.homes.homes) { home in
                            Button { appSession.selectHome(home) } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "house.fill").foregroundStyle(HomeyColors.primary).frame(width: 46, height: 46).background(HomeyColors.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(home.name).font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
                                        if let role = home.role { Text(role.displayName).font(.subheadline).foregroundStyle(HomeyColors.secondaryText) }
                                    }
                                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }.homeyCard()
                            }.buttonStyle(.plain)
                        }
                    }.padding(20)
                }
            }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sign Out") { Task { await appSession.signOut() } } } }
        }
    }
}
