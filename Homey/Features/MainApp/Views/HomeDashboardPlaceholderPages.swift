import SwiftUI

struct ListsView: View {
    var body: some View {
        PlaceholderModuleView(title: "Lists", subtitle: "Coming soon")
    }
}

struct ProjectsView: View {
    var body: some View {
        PlaceholderModuleView(title: "Projects", subtitle: "Coming soon")
    }
}

struct TripsView: View {
    var body: some View {
        PlaceholderModuleView(title: "Trips", subtitle: "Manage trips with other households")
    }
}

struct GroceriesView: View {
    var body: some View {
        PlaceholderModuleView(title: "Groceries", subtitle: "Coming soon")
    }
}

struct MessagesView: View {
    var body: some View {
        PlaceholderModuleView(title: "Messages", subtitle: "Coming soon")
    }
}

struct SettingsView: View {
    var body: some View {
        PlaceholderModuleView(title: "Settings", subtitle: "Coming soon")
    }
}

struct ManageHomeView: View {
    var body: some View {
        PlaceholderModuleView(title: "Manage Home", subtitle: "Coming soon")
    }
}

struct ChangeHomeView: View {
    var body: some View {
        PlaceholderModuleView(title: "Change Home", subtitle: "Coming soon")
    }
}

#Preview("Lists Placeholder") {
    ListsView()
}

#Preview("Projects Placeholder") {
    ProjectsView()
}

#Preview("Trips Placeholder") {
    TripsView()
}

#Preview("Groceries Placeholder") {
    GroceriesView()
}

#Preview("Messages Placeholder") {
    MessagesView()
}

#Preview("Settings Placeholder") {
    SettingsView()
}

#Preview("Manage Home Placeholder") {
    ManageHomeView()
}

#Preview("Change Home Placeholder") {
    ChangeHomeView()
}
