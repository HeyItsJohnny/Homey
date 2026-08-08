import Combine
import SwiftUI

struct MyRewardsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = MyRewardsViewModel()
    @State private var isAdjustRewardsPresented = false

    var body: some View {
        ChoreShellCard(title: "My Rewards", systemImage: "star.fill") {
            if let errorMessage = viewModel.errorMessage, viewModel.transactions.isEmpty, !viewModel.isLoading {
                ChoreMessageState(
                    title: "Unable to Load Rewards",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Try Again"
                ) {
                    viewModel.reload()
                }
            } else {
                rewardsContent
            }
        }
        .task(id: homeService.selectedHomeID) {
            await loadMembersIfNeeded()
            await configureViewModel()
        }
        .onChange(of: authenticationService.currentUser?.id) { _, _ in
            Task {
                await loadMembersIfNeeded()
                await configureViewModel()
            }
        }
        .onChange(of: homeService.membersForSelectedHome()) { _, _ in
            Task { await configureViewModel() }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                viewModel.reload()
            }
        }
        .sheet(isPresented: $isAdjustRewardsPresented) {
            if let homeId = homeService.selectedHomeID {
                AdjustRewardsView(
                    homeId: homeId,
                    members: viewModel.members,
                    initialSelectedUserId: viewModel.selectedMemberId ?? authenticationService.currentUser?.id,
                    currentRole: currentRole,
                    repository: viewModel.repository
                ) { adjustedUserId in
                    viewModel.selectAdjustedMember(adjustedUserId)
                }
            }
        }
    }

    private var rewardsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            rewardsHeader

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Points Activity")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                if viewModel.isLoading && viewModel.transactions.isEmpty {
                    MyRewardsLedgerLoadingView()
                } else if viewModel.transactions.isEmpty {
                    MyRewardsEmptyLedgerView()
                } else {
                    MyRewardsLedgerList(items: viewModel.displayItems)
                }

                if viewModel.hasMoreTransactions {
                    Button {
                        viewModel.loadMore()
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(HomeyDashboardTheme.warmBrown)
                            }
                            Text(viewModel.isLoadingMore ? "Loading..." : "Load More")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoadingMore)
                }
            }
        }
    }

    @ViewBuilder
    private var rewardsHeader: some View {
        if viewModel.canAdjustRewards && horizontalSizeClass != .compact {
            HStack(alignment: .bottom, spacing: 14) {
                if viewModel.canSelectMembers {
                    MyRewardsMemberSelector(
                        members: viewModel.members,
                        selectedMemberId: viewModel.selectedMemberId,
                        onSelect: { memberId in
                            viewModel.selectMember(memberId)
                        },
                        isCompact: true
                    )
                    .frame(maxWidth: 320)
                }

                MyRewardsBalanceCard(pointBalance: viewModel.pointBalance, isLoading: viewModel.isLoading, isCompact: true)
                    .frame(maxWidth: 260)

                Spacer(minLength: 12)

                adjustRewardsButton
                    .frame(width: 210)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if viewModel.canSelectMembers {
                    MyRewardsMemberSelector(
                        members: viewModel.members,
                        selectedMemberId: viewModel.selectedMemberId,
                        onSelect: { memberId in
                            viewModel.selectMember(memberId)
                        }
                    )
                }

                HStack(alignment: .bottom, spacing: 12) {
                    MyRewardsBalanceCard(pointBalance: viewModel.pointBalance, isLoading: viewModel.isLoading, isCompact: viewModel.canAdjustRewards)

                    if viewModel.canAdjustRewards {
                        adjustRewardsButton
                            .frame(width: 176)
                    }
                }
            }
        }
    }

    private var adjustRewardsButton: some View {
        Button {
            isAdjustRewardsPresented = true
        } label: {
            Label("Adjust Rewards", systemImage: "plusminus.circle.fill")
                .font(.subheadline.weight(.bold))
                .frame(minHeight: 42)
        }
        .buttonStyle(DashboardPrimaryButtonStyle())
        .accessibilityLabel("Adjust Rewards")
    }

    private var currentRole: HomeMemberRole? {
        homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
    }

    private func loadMembersIfNeeded() async {
        guard let selectedHomeID = homeService.selectedHomeID,
              let currentUser = authenticationService.currentUser else {
            return
        }

        await homeService.loadMembers(for: selectedHomeID, currentUser: currentUser)
    }

    private func configureViewModel() async {
        await viewModel.configure(
            homeId: homeService.selectedHomeID,
            currentUserId: authenticationService.currentUser?.id,
            currentRole: currentRole,
            members: homeService.membersForSelectedHome()
        )
    }
}

private struct MyRewardsMemberSelector: View {
    let members: [HomeMemberDisplay]
    let selectedMemberId: UUID?
    let onSelect: (UUID) -> Void
    var isCompact = false

    private var selectedMember: HomeMemberDisplay? {
        members.first { $0.userId == selectedMemberId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Member")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .textCase(.uppercase)

            Menu {
                ForEach(members) { member in
                    Button {
                        onSelect(member.userId)
                    } label: {
                        Label(member.displayName, systemImage: member.userId == selectedMemberId ? "checkmark" : "person")
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if let selectedMember {
                        AvatarView(
                            imageURL: selectedMember.avatarURL,
                            initials: selectedMember.initials,
                            size: isCompact ? 34 : 36,
                            accentColor: HomeyDashboardTheme.sageAccent,
                            borderColor: HomeyDashboardTheme.appBackground,
                            borderWidth: 2,
                            showsShadow: false,
                            accessibilityLabel: "\(selectedMember.displayName) avatar"
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedMember.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(HomeyDashboardTheme.primaryText)
                                .lineLimit(1)

                            if let email = selectedMember.email, !email.isEmpty {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text("Select Member")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: isCompact ? 86 : 58, alignment: .center)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Viewing rewards for \(selectedMember?.displayName ?? "selected member")")
        }
    }
}

private struct AdjustRewardsView: View {
    enum AdjustmentType: String, CaseIterable, Identifiable {
        case add
        case remove

        var id: String { rawValue }

        var title: String {
            switch self {
            case .add:
                return "Add"
            case .remove:
                return "Remove"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    let homeId: UUID
    let members: [HomeMemberDisplay]
    let initialSelectedUserId: UUID?
    let currentRole: HomeMemberRole?
    let repository: ChoresRepository
    let onSaved: (UUID) -> Void

    @State private var selectedUserId: UUID?
    @State private var adjustmentType: AdjustmentType = .add
    @State private var transactionDate = Date()
    @State private var amountText = ""
    @State private var description = ""
    @State private var selectedBalance = 0
    @State private var isLoadingBalance = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selectedMember: HomeMemberDisplay? {
        members.first { $0.userId == selectedUserId }
    }

    private var amount: Int? {
        Int(amountText)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var signedPoints: Int? {
        guard let amount, amount > 0 else {
            return nil
        }

        return adjustmentType == .add ? amount : -amount
    }

    private var validationMessage: String? {
        guard selectedUserId != nil else {
            return "Choose a member."
        }

        guard let amount, amount > 0 else {
            return "Enter a point amount greater than 0."
        }

        if adjustmentType == .remove && amount > selectedBalance {
            return "Cannot remove more points than this member currently has available."
        }

        guard !trimmedDescription.isEmpty else {
            return "Enter a description."
        }

        guard currentRole == .owner || currentRole == .admin else {
            return "Only Home owners and admins can adjust rewards."
        }

        return nil
    }

    private var canSave: Bool {
        validationMessage == nil && !isSaving && !isLoadingBalance
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    userField
                    adjustmentTypeField
                    dateField
                    amountField
                    descriptionField
                    balanceHint

                    if let visibleMessage = errorMessage ?? validationMessage {
                        Text(visibleMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(22)
            }
            .background(HomeyDashboardTheme.appBackground.ignoresSafeArea())
            .navigationTitle("Adjust Rewards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(HomeyDashboardTheme.warmBrown)
                        } else {
                            Text("Save Adjustment")
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .task {
            selectedUserId = initialSelectedUserId.flatMap { initialId in
                members.contains { $0.userId == initialId } ? initialId : nil
            } ?? members.first?.userId
            await loadSelectedBalance()
        }
        .onChange(of: selectedUserId) { _, _ in
            Task { await loadSelectedBalance() }
        }
        .presentationDetents([.large])
    }

    private var userField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("User")
            Menu {
                ForEach(members) { member in
                    Button {
                        selectedUserId = member.userId
                    } label: {
                        Label(member.displayName, systemImage: member.userId == selectedUserId ? "checkmark" : "person")
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if let selectedMember {
                        AvatarView(
                            imageURL: selectedMember.avatarURL,
                            initials: selectedMember.initials,
                            size: 36,
                            accentColor: HomeyDashboardTheme.sageAccent,
                            borderColor: HomeyDashboardTheme.appBackground,
                            borderWidth: 2,
                            showsShadow: false,
                            accessibilityLabel: "\(selectedMember.displayName) avatar"
                        )
                        Text(selectedMember.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                            .lineLimit(1)
                    } else {
                        Text("Select Member")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                    }

                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(adjustmentFieldBackground)
            }
            .buttonStyle(.plain)
        }
    }

    private var adjustmentTypeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Adjustment Type")
            HStack(spacing: 10) {
                adjustmentTypeButton(.add)
                adjustmentTypeButton(.remove)
            }
        }
    }

    private func adjustmentTypeButton(_ type: AdjustmentType) -> some View {
        let isSelected = adjustmentType == type
        let color = type == .add ? HomeyDashboardTheme.sageAccent : HomeyDashboardTheme.destructiveRed
        return Button {
            adjustmentType = type
        } label: {
            Text(type.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isSelected ? .white : color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isSelected ? color.opacity(0.9) : color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(color.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.title)
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Date & Time")
            DatePicker("Date & Time", selection: $transactionDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(adjustmentFieldBackground)
                .accessibilityLabel("Date and time")
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Point Amount")
            TextField("25", text: $amountText)
                .keyboardType(.numberPad)
                .font(.body.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(16)
                .background(adjustmentFieldBackground)
                .onChange(of: amountText) { _, newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != newValue {
                        amountText = filtered
                    }
                }
                .accessibilityLabel("Point amount")
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Description")
            TextField("Bonus for helping with groceries", text: $description, axis: .vertical)
                .lineLimit(3...5)
                .font(.body)
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(16)
                .background(adjustmentFieldBackground)
                .accessibilityLabel("Description")
        }
    }

    @ViewBuilder
    private var balanceHint: some View {
        if isLoadingBalance {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(HomeyDashboardTheme.warmBrown)
                Text("Loading available points...")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
        } else {
            Text("Available points: \(selectedBalance.formatted(.number))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private var adjustmentFieldBackground: some ShapeStyle {
        HomeyDashboardTheme.cardBackground
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.primaryText)
    }

    private func loadSelectedBalance() async {
        guard let selectedUserId else {
            selectedBalance = 0
            return
        }

        isLoadingBalance = true
        errorMessage = nil
        do {
            selectedBalance = try await repository.fetchPointBalance(homeId: homeId, userId: selectedUserId, currentRole: currentRole)
        } catch {
            selectedBalance = 0
            errorMessage = error.localizedDescription
        }
        isLoadingBalance = false
    }

    private func save() async {
        guard let selectedUserId, let signedPoints else {
            errorMessage = validationMessage
            return
        }

        guard validationMessage == nil else {
            errorMessage = validationMessage
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await repository.adjustChorePoints(
                homeId: homeId,
                userId: selectedUserId,
                points: signedPoints,
                description: trimmedDescription,
                transactionAt: transactionDate,
                currentRole: currentRole
            )
            onSaved(selectedUserId)
            dismiss()
        } catch {
            errorMessage = "Unable to save adjustment."
        }
    }
}

private struct MyRewardsBalanceCard: View {
    let pointBalance: Int
    let isLoading: Bool
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            Text("Total Available Points")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .tint(HomeyDashboardTheme.warmBrown)
                    .accessibilityLabel("Loading total available points")
            } else {
                Text(pointBalance.formatted(.number))
                    .font(.system(size: isCompact ? 30 : 46, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .padding(isCompact ? 14 : 18)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 86 : 150, alignment: .leading)
        .dashboardCard(cornerRadius: isCompact ? 16 : 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLoading ? "Total available points loading" : "Total Available Points, \(pointBalance.formatted(.number))")
    }
}

private struct MyRewardsLedgerList: View {
    let items: [MyRewardsLedgerItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                MyRewardsLedgerRow(item: item)

                if item.id != items.last?.id {
                    Divider()
                        .overlay(HomeyDashboardTheme.softBorder)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

private struct MyRewardsLedgerRow: View {
    let item: MyRewardsLedgerItem

    private var transaction: ChorePointTransaction { item.transaction }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)

                Text(transaction.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                Text(transaction.transactionType.rewardsDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer(minLength: 10)

            Text(pointsText)
                .font(.headline.weight(.bold))
                .foregroundStyle(pointsColor)
                .lineLimit(1)
                .accessibilityLabel(pointsAccessibilityText)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(transaction.createdAt.formatted(date: .abbreviated, time: .shortened)). \(pointsAccessibilityText). \(transaction.transactionType.rewardsDisplayName).")
    }

    private var title: String {
        if let displayTitle = item.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !displayTitle.isEmpty {
            return displayTitle
        }

        if let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return note
        }

        return transaction.transactionType.rewardsDisplayName
    }

    private var pointsText: String {
        transaction.pointsDelta >= 0 ? "+\(transaction.pointsDelta)" : "\(transaction.pointsDelta)"
    }

    private var pointsAccessibilityText: String {
        transaction.pointsDelta >= 0 ? "Increased by \(transaction.pointsDelta) points" : "Decreased by \(abs(transaction.pointsDelta)) points"
    }

    private var pointsColor: Color {
        transaction.pointsDelta >= 0 ? HomeyDashboardTheme.sageAccent : HomeyDashboardTheme.destructiveRed
    }
}

private struct MyRewardsLedgerItem: Identifiable, Hashable {
    let transaction: ChorePointTransaction
    let displayTitle: String?

    var id: UUID { transaction.id }
}

private struct MyRewardsEmptyLedgerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No point activity yet.")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text("Complete chores to start earning points.")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

private struct MyRewardsLedgerLoadingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(HomeyDashboardTheme.warmBrown)
            Text("Loading point activity...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

@MainActor
private final class MyRewardsViewModel: ObservableObject {
    @Published private(set) var pointBalance = 0
    @Published private(set) var transactions: [ChorePointTransaction] = []
    @Published private(set) var displayItems: [MyRewardsLedgerItem] = []
    @Published private(set) var members: [HomeMemberDisplay] = []
    @Published private(set) var selectedMemberId: UUID?
    @Published private(set) var canSelectMembers = false
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreTransactions = false
    @Published private(set) var errorMessage: String?

    let repository: ChoresRepository
    private let pageSize = 10
    private var activeHomeId: UUID?
    private var currentUserId: UUID?
    private var currentRole: HomeMemberRole?
    private var activeLoadId = UUID()

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    var canAdjustRewards: Bool {
        (currentRole == .owner || currentRole == .admin) && !members.isEmpty
    }

    func configure(homeId: UUID?, currentUserId: UUID?, currentRole: HomeMemberRole?, members: [HomeMemberDisplay]) async {
        guard let homeId, let currentUserId else {
            reset()
            return
        }

        let sortedMembers = HomeMemberDisplay.sorted(members)
        let canSelectMembers = (currentRole == .owner || currentRole == .admin) && !sortedMembers.isEmpty
        let previousHomeId = activeHomeId
        let previousSelectedMemberId = selectedMemberId

        activeHomeId = homeId
        self.currentUserId = currentUserId
        self.currentRole = currentRole
        self.members = sortedMembers
        self.canSelectMembers = canSelectMembers

        let validSelection = selectedMemberId.flatMap { selectedId in
            sortedMembers.contains { $0.userId == selectedId } ? selectedId : nil
        }
        let nextSelectedMemberId = canSelectMembers ? (validSelection ?? currentUserId) : currentUserId
        selectedMemberId = nextSelectedMemberId

        if previousHomeId != homeId || previousSelectedMemberId != nextSelectedMemberId || transactions.isEmpty {
            await loadSelectedMember(resetLedger: true)
        }
    }

    func selectMember(_ memberId: UUID) {
        guard canSelectMembers,
              members.contains(where: { $0.userId == memberId }),
              selectedMemberId != memberId else {
            return
        }

        selectedMemberId = memberId
        Task {
            await loadSelectedMember(resetLedger: true)
        }
    }

    func selectAdjustedMember(_ memberId: UUID) {
        guard canSelectMembers, members.contains(where: { $0.userId == memberId }) else {
            reload()
            return
        }

        selectedMemberId = memberId
        Task {
            await loadSelectedMember(resetLedger: true)
        }
    }

    func loadMore() {
        guard let activeHomeId,
              let selectedMemberId,
              !isLoadingMore,
              !isLoading,
              hasMoreTransactions else {
            return
        }

        let loadingMemberId = selectedMemberId
        let loadingRole = currentRole
        isLoadingMore = true
        errorMessage = nil

        Task {
            defer { isLoadingMore = false }

            do {
                let nextPage = try await repository.fetchPointTransactions(
                    homeId: activeHomeId,
                    userId: loadingMemberId,
                    limit: pageSize,
                    offset: transactions.count,
                    currentRole: loadingRole
                )
                let nextItems = await makeDisplayItems(for: nextPage)
                guard self.selectedMemberId == loadingMemberId else {
                    return
                }
                transactions.append(contentsOf: nextPage)
                displayItems.append(contentsOf: nextItems)
                hasMoreTransactions = nextPage.count == pageSize
            } catch {
                errorMessage = error.localizedDescription
            }

        }
    }

    func reload() {
        Task {
            await loadSelectedMember(resetLedger: true)
        }
    }

    private func reset() {
        activeHomeId = nil
        currentUserId = nil
        currentRole = nil
        members = []
        selectedMemberId = nil
        canSelectMembers = false
        pointBalance = 0
        transactions = []
        displayItems = []
        errorMessage = nil
        hasMoreTransactions = false
        isLoading = false
        isLoadingMore = false
    }

    private func loadSelectedMember(resetLedger: Bool) async {
        guard let activeHomeId, let selectedMemberId else {
            reset()
            return
        }

        let loadId = UUID()
        activeLoadId = loadId
        isLoading = true
        isLoadingMore = false
        errorMessage = nil

        if resetLedger {
            pointBalance = 0
            transactions = []
            displayItems = []
            hasMoreTransactions = false
        }

        do {
            async let loadedBalance = repository.fetchPointBalance(homeId: activeHomeId, userId: selectedMemberId, currentRole: currentRole)
            async let loadedTransactions = repository.fetchPointTransactions(
                homeId: activeHomeId,
                userId: selectedMemberId,
                limit: pageSize,
                offset: 0,
                currentRole: currentRole
            )
            let loadedPointBalance = try await loadedBalance
            let firstPage = try await loadedTransactions
            let firstItems = await makeDisplayItems(for: firstPage)
            guard activeLoadId == loadId, self.selectedMemberId == selectedMemberId else {
                return
            }
            pointBalance = loadedPointBalance
            transactions = firstPage
            displayItems = firstItems
            hasMoreTransactions = firstPage.count == pageSize
        } catch {
            guard activeLoadId == loadId, self.selectedMemberId == selectedMemberId else {
                return
            }
            pointBalance = 0
            transactions = []
            displayItems = []
            hasMoreTransactions = false
            errorMessage = error.localizedDescription
        }

        if activeLoadId == loadId {
            isLoading = false
        }
    }

    private func makeDisplayItems(for transactions: [ChorePointTransaction]) async -> [MyRewardsLedgerItem] {
        let titles = await repository.fetchPointTransactionDisplayTitles(for: transactions)
        return transactions.map { transaction in
            MyRewardsLedgerItem(transaction: transaction, displayTitle: titles[transaction.id])
        }
    }
}

private extension ChorePointTransactionType {
    var rewardsDisplayName: String {
        switch self {
        case .choreEarned:
            return "Chore Earned"
        case .adminAdjustment:
            return "Adjustment"
        case .rewardRedemption:
            return "Reward Redeemed"
        case .rewardRefund:
            return "Reward Refund"
        }
    }
}
