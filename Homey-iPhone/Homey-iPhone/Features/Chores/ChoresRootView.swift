import SwiftUI

enum ChoresSection: String, CaseIterable, Identifiable {
    case chores = "Chores"
    case approvals = "Approvals"
    case rewards = "Rewards"
    case history = "History"

    var id: Self { self }
}

struct ChoresRootView: View {
    @EnvironmentObject private var appSession: AppSession
    @State private var section: ChoresSection = .chores
    @State private var creationDestination: ChoreCreationPlaceholder?
    @State private var refreshToken = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()

                VStack(spacing: 12) {
                    header

                    Picker("Chores", selection: $section) {
                        ForEach(ChoresSection.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    selectedContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Chores")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $creationDestination) { destination in
                if destination == .roomAndChores {
                    RoomChoreSetupView(
                        homeID: appSession.activeHome?.id,
                        role: appSession.activeRole,
                        timezone: appSession.activeTimezone.identifier
                    ) {
                        refreshToken = UUID()
                    }
                } else {
                    ChoreCreationPlaceholderView(destination: destination)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Chores")
                .font(.title.bold())
                .foregroundStyle(HomeyColors.text)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if section == .chores {
                Menu {
                    Section("Automation") {
                        Button("Add Room and Chores", systemImage: "wand.and.sparkles") {
                            creationDestination = .roomAndChores
                        }
                    }
                    Section("Manual") {
                        Button("Add Chore", systemImage: "checkmark.circle") {
                            creationDestination = .chore
                        }
                        Button("Add Room", systemImage: "door.left.hand.open") {
                            creationDestination = .room
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(HomeyColors.primary)
                        .frame(width: 44, height: 44)
                        .background(HomeyColors.field, in: Circle())
                }
                .accessibilityLabel("Chore actions")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch section {
        case .chores:
            ChoresMainView()
                .id(refreshToken)
        case .approvals:
            ChoreApprovalsView()
        case .rewards:
            ChoreRewardsView()
        case .history:
            ChoreHistoryView()
        }
    }
}

private enum ChoreCreationPlaceholder: String, Identifiable {
    case roomAndChores = "Add Room and Chores"
    case chore = "Add Chore"
    case room = "Add Room"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .roomAndChores: "wand.and.sparkles"
        case .chore: "checkmark.circle"
        case .room: "door.left.hand.open"
        }
    }
}

private struct ChoreCreationPlaceholderView: View {
    let destination: ChoreCreationPlaceholder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChorePlaceholderView(
                title: destination.rawValue,
                message: "This form will be added in the next Chores phase.",
                symbol: destination.symbol
            )
            .navigationTitle(destination.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
