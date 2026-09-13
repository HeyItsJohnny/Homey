import SwiftUI

struct ChoresMainView: View {
    var body: some View {
        ChorePlaceholderView(
            title: "Chores",
            message: "Your chores will appear here.",
            symbol: "checklist"
        )
    }
}

struct ChoreApprovalsView: View {
    var body: some View {
        ChorePlaceholderView(
            title: "Approvals",
            message: "Chore approvals will appear here.",
            symbol: "checkmark.seal"
        )
    }
}

struct ChoreRewardsView: View {
    var body: some View {
        ChorePlaceholderView(
            title: "Rewards",
            message: "Rewards will appear here.",
            symbol: "gift"
        )
    }
}

struct ChoreHistoryView: View {
    var body: some View {
        ChorePlaceholderView(
            title: "History",
            message: "Completed chore history will appear here.",
            symbol: "clock.arrow.circlepath"
        )
    }
}

struct ChorePlaceholderView: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(HomeyColors.primary)
                    .frame(width: 72, height: 72)
                    .background(HomeyColors.field, in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(HomeyTypography.headline)
                    .foregroundStyle(HomeyColors.text)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 28)
        }
    }
}
