import SwiftUI

struct RoomCleaningSummaryView: View {
    let summary: RoomCleaningSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(width: 28, height: 28)
                    .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.room.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(1)

                    Text(summary.room.displayRoomType.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                summaryRow("Last Cleaned", value: lastCleanedText)
                summaryRow("Preferred Cleaning", value: summary.preferredCleaningText)
            }
        }
        .padding(12)
        .background(HomeyDashboardTheme.cardBackground.opacity(0.74), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.78), lineWidth: 1)
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            Spacer(minLength: 8)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var lastCleanedText: String {
        guard let lastCleanedAt = summary.lastCleanedAt else {
            return "Never"
        }

        return lastCleanedAt.formatted(date: .abbreviated, time: .omitted)
    }
}
