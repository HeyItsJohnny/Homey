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
    var body: some View {
        NavigationStack {
            List {
                Section("Profile") { LabeledContent("Name", value: appSession.currentUser?.preferredDisplayName ?? "—"); LabeledContent("Email", value: appSession.currentUser?.email ?? "—") }
                Section("Active Home") { LabeledContent("Home", value: appSession.activeHome?.name ?? "—"); LabeledContent("Role", value: appSession.activeRole?.displayName ?? "—") }
                Section { Button("Sign Out", role: .destructive) { Task { dismiss(); await appSession.signOut() } } }
            }.navigationTitle("Profile").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
