import SwiftUI

struct MealPhotoThumbnail: View {
    let path: String?
    @State private var signedURL: URL?
    @State private var didFail = false
    private let mealService = MealService()

    var body: some View {
        ZStack {
            if let signedURL, !didFail {
                AsyncImage(url: signedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                            .onAppear { didFail = true }
                    case .empty:
                        ProgressView()
                            .tint(HomeyDashboardTheme.warmBrown)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: path) {
            await loadSignedURL()
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [HomeyDashboardTheme.warmBeige.opacity(0.82), HomeyDashboardTheme.selectedSidebarBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "fork.knife")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
        }
        .accessibilityHidden(true)
    }

    private func loadSignedURL() async {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            signedURL = nil
            return
        }

        do {
            signedURL = try await mealService.createSignedMealPhotoURL(path: path)
            didFail = false
        } catch {
            signedURL = nil
            didFail = true
        }
    }
}
