import SwiftUI

struct AvatarView: View {
    let imageURL: URL?
    let initials: String
    var size: CGFloat
    var accentColor: Color = HomeyDashboardTheme.warmBrown
    var borderColor: Color = HomeyDashboardTheme.cardBackground
    var borderWidth: CGFloat = 3
    var showsShadow = true
    var isLoading = false
    var accessibilityLabel: String = "Profile avatar"

    var body: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.22))

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .tint(HomeyDashboardTheme.warmBrown)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }

            if isLoading {
                Circle()
                    .fill(.black.opacity(0.22))

                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Updating avatar")
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(borderColor, lineWidth: borderWidth)
        }
        .shadow(
            color: HomeyDashboardTheme.primaryText.opacity(showsShadow ? 0.12 : 0),
            radius: showsShadow ? max(8, size * 0.12) : 0,
            x: 0,
            y: showsShadow ? max(4, size * 0.06) : 0
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var initialsView: some View {
        Text(sanitizedInitials)
            .font(.system(size: max(12, size * 0.34), weight: .bold, design: .rounded))
            .foregroundStyle(accentColor)
    }

    private var sanitizedInitials: String {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "HM" : trimmed
    }
}
