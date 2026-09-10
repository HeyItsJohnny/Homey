import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appSession: AppSession
    @StateObject private var viewModel = HomeDashboardViewModel()
    @State private var showingProfile = false
    let navigate: (DashboardDestination) -> Void

    private var firstName: String? {
        let value = appSession.currentUser?.displayName ?? appSession.currentUser?.firstName
        return value?.split(separator: " ").first.map(String.init)
    }

    var body: some View {
        ZStack {
            HomeyBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    header
                    attentionSection
                    quickActionsSection
                    upcomingSection
                    groceryAndWeekSection
                    if !viewModel.snapshot.failedSections.isEmpty { partialFailure }
                }.padding(.horizontal, 18).padding(.vertical, 16)
            }.refreshable { await refresh(force: true) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: appSession.activeHome?.id) { await refresh(force: true) }
        .onAppear { Task { await refresh() } }
        .sheet(isPresented: $showingProfile) { ProfileSheet() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("HOMEY", systemImage: "house.fill").font(.caption.weight(.bold)).foregroundStyle(HomeyColors.primary)
                Text(greeting).font(HomeyTypography.title).foregroundStyle(HomeyColors.text)
                Text(appSession.activeHome?.name ?? "Your Home").font(.subheadline.weight(.medium)).foregroundStyle(HomeyColors.secondaryText)
            }
            Spacer()
            Button { showingProfile = true } label: {
                Text(appSession.currentUser?.initials ?? "HM").font(.subheadline.bold()).foregroundStyle(HomeyColors.primary).frame(width: 44, height: 44).background(.white.opacity(0.92), in: Circle()).overlay { Circle().stroke(HomeyColors.primary.opacity(0.18)) }
            }.accessibilityLabel("Open profile")
        }
    }

    private var attentionSection: some View {
        DashboardSectionView(title: "Needs Attention") {
            if viewModel.isLoading && viewModel.lastLoadedAt == nil {
                HStack { ProgressView(); Text("Checking your household…").foregroundStyle(HomeyColors.secondaryText) }.frame(maxWidth: .infinity, alignment: .leading).homeyCard()
            } else if viewModel.snapshot.attentionItems.isEmpty {
                HStack(spacing: 14) { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(HomeyColors.success); VStack(alignment: .leading) { Text("You're all caught up.").font(.headline); Text("Nothing needs your attention right now.").font(.subheadline).foregroundStyle(HomeyColors.secondaryText) } }.frame(maxWidth: .infinity, alignment: .leading).homeyCard()
            } else {
                ForEach(viewModel.snapshot.attentionItems) { item in DashboardRow(title: item.title, detail: item.detail, systemImage: item.systemImage, tint: HomeyColors.danger) { navigate(item.destination) } }
            }
        }
    }

    private var quickActionsSection: some View {
        DashboardSectionView(title: "Quick Actions") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if appSession.activeRole == .owner || appSession.activeRole == .admin {
                        QuickAction(title: "Add Chore", icon: "plus.circle.fill") { navigate(.chores) }
                    }
                    QuickAction(title: "Add Event", icon: "calendar.badge.plus") { navigate(.calendar) }
                    QuickAction(title: "Plan Meals", icon: "fork.knife") { navigate(.meals) }
                    QuickAction(title: "Add Recipe", icon: "book.closed.fill") { navigate(.meals) }
                    QuickAction(title: "Add Item", icon: "cart.badge.plus") { navigate(.groceries) }
                }
            }.contentMargins(.horizontal, 1)
        }
    }

    private var upcomingSection: some View {
        DashboardSectionView(title: "Upcoming") {
            if let meal = viewModel.snapshot.tonightMeal { DashboardRow(title: "Tonight", detail: meal, systemImage: "fork.knife", tint: HomeyColors.primary) { navigate(.meals) } }
            if let count = viewModel.snapshot.choresDueToday { DashboardRow(title: "Chores Today", detail: count == 0 ? "Nothing scheduled" : "\(count) chore\(count == 1 ? "" : "s") scheduled", systemImage: "checklist", tint: Color.orange) { navigate(.chores) } }
            ForEach(viewModel.snapshot.upcomingEvents.prefix(3)) { item in DashboardRow(title: item.title, detail: item.detail, systemImage: "calendar", tint: Color(hex: item.colorHex) ?? HomeyColors.primary) { navigate(.calendar) } }
            if viewModel.snapshot.tonightMeal == nil, viewModel.snapshot.choresDueToday == nil, viewModel.snapshot.upcomingEvents.isEmpty, !viewModel.isLoading {
                Text("No upcoming details are available.").font(.subheadline).foregroundStyle(HomeyColors.secondaryText).frame(maxWidth: .infinity, alignment: .leading).homeyCard()
            }
        }
    }

    private var groceryAndWeekSection: some View {
        DashboardSectionView(title: "This Week") {
            Button { navigate(.groceries) } label: { HStack { Label("Groceries", systemImage: "cart.fill"); Spacer(); Text("Open list").foregroundStyle(HomeyColors.secondaryText); Image(systemName: "chevron.right") }.foregroundStyle(HomeyColors.text).homeyCard() }.buttonStyle(.plain)
            HStack(spacing: 12) {
                WeekMetric(value: viewModel.snapshot.dinnersPlanned.map { "\($0)/7" } ?? "—", label: "Dinners")
                WeekMetric(value: viewModel.snapshot.upcomingEventCount.map(String.init) ?? "—", label: "Events")
                WeekMetric(value: viewModel.snapshot.choresDueToday.map(String.init) ?? "—", label: "Chores Today")
            }
        }
    }

    private var partialFailure: some View { Label("Some household details couldn't be refreshed. Pull down to try again.", systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(HomeyColors.secondaryText).padding(.bottom, 12) }
    private var greeting: String { let hour = Calendar.current.component(.hour, from: Date()); let part = hour < 12 ? "Good Morning" : hour < 17 ? "Good Afternoon" : "Good Evening"; return firstName.map { "\(part), \($0)" } ?? part }
    private func refresh(force: Bool = false) async { guard let home = appSession.activeHome else { return }; await viewModel.load(home: home, role: appSession.activeRole, force: force) }
}

private struct DashboardSectionView<Content: View>: View {
    let title: String; @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(HomeyTypography.headline).foregroundStyle(HomeyColors.text); content } }
}

private struct DashboardRow: View {
    let title, detail, systemImage: String; let tint: Color; let action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 14) { Image(systemName: systemImage).font(.title3).foregroundStyle(tint).frame(width: 42, height: 42).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(HomeyColors.secondaryText) }; Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }.foregroundStyle(HomeyColors.text).frame(maxWidth: .infinity, alignment: .leading).homeyCard() }.buttonStyle(.plain) }
}

private struct QuickAction: View {
    let title, icon: String; let action: () -> Void
    var body: some View { Button(action: action) { VStack(alignment: .leading, spacing: 12) { Image(systemName: icon).font(.title3).foregroundStyle(HomeyColors.primary); Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text).lineLimit(1) }.frame(width: 92, height: 72, alignment: .leading).padding(14).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(HomeyColors.primary.opacity(0.10)) } }.buttonStyle(.plain) }
}

private struct WeekMetric: View {
    let value, label: String
    var body: some View { VStack(spacing: 5) { Text(value).font(.title3.bold()).foregroundStyle(HomeyColors.primary); Text(label).font(.caption2).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.center).lineLimit(2) }.frame(maxWidth: .infinity).frame(height: 72).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16)) }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }; let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
