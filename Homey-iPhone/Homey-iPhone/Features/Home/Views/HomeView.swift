import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appSession: AppSession
    @StateObject private var viewModel = HomeDashboardViewModel()
    @State private var showingProfile = false
    @State private var showingHomeSettings = false
    @State private var showingMembers = false
    let navigate: (DashboardDestination) -> Void

    private var firstName: String? {
        let value = appSession.currentUser?.displayName ?? appSession.currentUser?.firstName
        return value?.split(separator: " ").first.map(String.init)
    }

    private var dashboardScope: String {
        "\(appSession.activeHome?.id.uuidString ?? "no-home")-\(appSession.currentUser?.id.uuidString ?? "no-user")-\(appSession.activeRole?.rawValue ?? "no-role")"
    }

    var body: some View {
        ZStack {
            HomeyBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    header
                    attentionSection
                    todayEventsSection
                    todayMealsSection
                    todayChoresSection
                    mealCountsSection
                    if !viewModel.snapshot.failedSections.isEmpty { partialFailure }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .refreshable { await refresh(force: true) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: dashboardScope) { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyChoresDidChange"))) { _ in
            Task { await refresh(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyCalendarEventsDidChange"))) { _ in
            Task { await refresh(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyMealsDidChange"))) { _ in
            Task { await refresh(force: true) }
        }
        .sheet(isPresented: $showingProfile) { ProfileSheet() }
        .sheet(isPresented: $showingHomeSettings) {
            NavigationStack {
                HomeSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingHomeSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingMembers) {
            NavigationStack {
                HomeMembersView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingMembers = false }
                        }
                    }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("HOMEY", systemImage: "house.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyColors.primary)
                Text(greeting).font(HomeyTypography.title).foregroundStyle(HomeyColors.text)
                Text(appSession.activeHome?.name ?? "Your Home")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeyColors.secondaryText)
            }
            Spacer()
            Menu {
                Button { showingProfile = true } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                Button { showingHomeSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .disabled(appSession.activeHome == nil)
                Button { showingMembers = true } label: {
                    Label("Members", systemImage: "person.2")
                }
                .disabled(appSession.activeHome == nil)
            } label: {
                ProfileAvatarView(profile: appSession.currentUser, size: 44)
            }
            .accessibilityLabel("Open profile menu")
        }
    }

    private var attentionSection: some View {
        DashboardSectionView(title: "Needs Attention") {
            if viewModel.isLoading && viewModel.lastLoadedAt == nil {
                HStack {
                    ProgressView()
                    Text("Checking your household…").foregroundStyle(HomeyColors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .homeyCard()
            } else if viewModel.snapshot.attentionItems.isEmpty {
                DashboardEmptyState(
                    title: "You're all caught up.",
                    detail: "Nothing needs your attention right now.",
                    symbol: "checkmark.circle.fill"
                )
            } else {
                ForEach(viewModel.snapshot.attentionItems) { item in
                    DashboardRow(title: item.title, detail: item.detail, systemImage: item.systemImage, tint: HomeyColors.danger) {
                        navigate(item.destination)
                    }
                }
            }
        }
    }

    private var todayEventsSection: some View {
        DashboardSectionView(title: "Today’s Events") {
            if viewModel.isLoading && viewModel.lastLoadedAt == nil {
                DashboardLoadingCard()
            } else if !viewModel.snapshot.calendarDataLoaded {
                DashboardUnavailableCard(detail: "Today's events couldn't be refreshed.")
            } else if viewModel.snapshot.todayEvents.isEmpty {
                DashboardEmptyState(title: "Nothing scheduled today", detail: "Your day is open.", symbol: "calendar.badge.checkmark")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.snapshot.todayEvents.enumerated()), id: \.element.id) { index, event in
                        Button { navigate(.calendar) } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: event.colorHex) ?? HomeyColors.primary)
                                    .frame(width: 10, height: 10)
                                Text(event.isAllDay ? "All day" : eventTimeFormatter.string(from: event.startsAt))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(HomeyColors.secondaryText)
                                    .frame(width: 58, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text)
                                    if let location = event.location {
                                        Label(location, systemImage: "mappin.and.ellipse")
                                            .font(.caption)
                                            .foregroundStyle(HomeyColors.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if index < viewModel.snapshot.todayEvents.count - 1 { Divider() }
                    }
                }
                .homeyCard()
            }
        }
    }

    private var todayMealsSection: some View {
        DashboardSectionView(title: "Today’s Meals") {
            if viewModel.isLoading && viewModel.lastLoadedAt == nil {
                DashboardLoadingCard()
            } else if !viewModel.snapshot.mealDataLoaded {
                DashboardUnavailableCard(detail: "Today's meals couldn't be refreshed.")
            } else if viewModel.snapshot.todayMeals.isEmpty {
                DashboardEmptyState(title: "Nothing planned today", detail: "Your meal plan is ready when you are.", symbol: "fork.knife")
            } else {
                Button { navigate(.meals) } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach([MealType.breakfast, .lunch, .dinner]) { type in
                            let meals = viewModel.snapshot.todayMeals.filter { $0.mealType == type }
                            if !meals.isEmpty {
                                VStack(alignment: .leading, spacing: 9) {
                                    Label(type.title, systemImage: type.symbol)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(HomeyColors.primary)
                                    ForEach(meals) { meal in
                                        HStack(spacing: 12) {
                                            HomeRecipeThumbnail(path: meal.photoPath)
                                                .frame(width: 44, height: 44)
                                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                            Text(meal.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(HomeyColors.text)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .homeyCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var todayChoresSection: some View {
        DashboardSectionView(title: "Today’s Chores") {
            if !viewModel.snapshot.choreRoleResolved {
                DashboardEmptyState(
                    title: "Resolving chore access",
                    detail: "Household permissions are still loading.",
                    symbol: "person.badge.shield.checkmark"
                )
            } else if viewModel.isLoading && viewModel.lastLoadedAt == nil {
                DashboardLoadingCard()
            } else if !viewModel.snapshot.choreDataLoaded {
                DashboardUnavailableCard(detail: "Today's chores couldn't be refreshed.")
            } else if viewModel.snapshot.todayChores.isEmpty {
                DashboardEmptyState(
                    title: appSession.activeRole == .member ? "You're all caught up today" : "No chores scheduled today",
                    detail: "Everything scheduled for today is clear.",
                    symbol: "checklist.checked"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.snapshot.todayChores.enumerated()), id: \.element.id) { index, chore in
                        Button { navigate(.chores) } label: {
                            DashboardChoreRow(chore: chore, showsAssignees: appSession.activeRole == .owner || appSession.activeRole == .admin)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if index < viewModel.snapshot.todayChores.count - 1 { Divider() }
                    }
                }
                .homeyCard()
            }
        }
    }

    private var mealCountsSection: some View {
        DashboardSectionView(title: "Meals Planned This Week") {
            Button { navigate(.meals) } label: {
                HStack(spacing: 12) {
                    MealCountMetric(type: .breakfast, count: mealCount(.breakfast))
                    MealCountMetric(type: .lunch, count: mealCount(.lunch))
                    MealCountMetric(type: .dinner, count: mealCount(.dinner))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var partialFailure: some View {
        Label("Some household details couldn't be refreshed. Pull down to try again.", systemImage: "wifi.exclamationmark")
            .font(.footnote)
            .foregroundStyle(HomeyColors.secondaryText)
            .padding(.bottom, 12)
    }

    private var eventTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = appSession.activeTimezone
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good Morning" : hour < 17 ? "Good Afternoon" : "Good Evening"
        return firstName.map { "\(part), \($0)" } ?? part
    }

    private func refresh(force: Bool = false) async {
        guard let home = appSession.activeHome else { return }
        await viewModel.load(
            home: home,
            currentUserID: appSession.currentUser?.id,
            role: appSession.activeRole,
            force: force
        )
    }

    private func mealCount(_ type: MealType) -> Int? {
        viewModel.snapshot.mealCountsDataLoaded ? viewModel.snapshot.mealCounts[type] : nil
    }
}

private struct DashboardSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
            content
        }
    }
}

private struct DashboardRow: View {
    let title, detail, systemImage: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .foregroundStyle(HomeyColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeyCard()
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardEmptyState: View {
    let title, detail, symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(HomeyColors.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(HomeyColors.text)
                Text(detail).font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeyCard()
    }
}

private struct DashboardLoadingCard: View {
    var body: some View {
        HStack { ProgressView(); Text("Loading today…").foregroundStyle(HomeyColors.secondaryText) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeyCard()
    }
}

private struct DashboardUnavailableCard: View {
    let detail: String
    var body: some View {
        Label(detail, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(HomeyColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeyCard()
    }
}

private struct DashboardChoreRow: View {
    let chore: DashboardTodayChore
    let showsAssignees: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 36, height: 36)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(chore.title).font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text)
                HStack(spacing: 5) {
                    Text(chore.status.displayName)
                    if let roomName = chore.roomName { Text("•"); Text(roomName) }
                    if showsAssignees, !chore.assigneeNames.isEmpty {
                        Text("•")
                        Text(chore.assigneeNames.joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundStyle(HomeyColors.secondaryText)
                .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
    }

    private var statusSymbol: String {
        switch chore.status {
        case .notStarted: "circle"
        case .inProgress: "clock.arrow.circlepath"
        case .awaitingApproval: "checkmark.seal"
        case .completed: "checkmark.circle.fill"
        case .needsRedo: "arrow.counterclockwise.circle.fill"
        case .skipped: "forward.end.circle"
        case .cancelled: "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch chore.status {
        case .completed: HomeyColors.success
        case .needsRedo: HomeyColors.danger
        case .awaitingApproval: HomeyColors.primary
        case .inProgress: .orange
        case .notStarted, .skipped, .cancelled: HomeyColors.secondaryText
        }
    }
}

private struct MealCountMetric: View {
    let type: MealType
    let count: Int?
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: type.symbol).foregroundStyle(HomeyColors.primary)
            Text(count.map { "\($0)/7" } ?? "—/7").font(.title3.bold()).foregroundStyle(HomeyColors.text)
            Text(type.title).font(.caption2).foregroundStyle(HomeyColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 86)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255
        )
    }
}
