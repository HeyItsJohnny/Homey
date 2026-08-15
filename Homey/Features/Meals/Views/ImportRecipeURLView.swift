import SwiftUI

struct ImportRecipeURLView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let service = RecipeImportService()
    @State private var urlText = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    let homeId: UUID?
    var onImported: (RecipeImportResponse) -> Void

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Paste a public recipe link and Homey will look for recipe details it can import.")
                            .font(.body)
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recipe URL")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            TextField("https://example.com/recipe", text: $urlText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .submitLabel(.go)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { Task { await importRecipe() } }
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeyDashboardTheme.softRed)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(HomeyDashboardTheme.softRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeyDashboardTheme.softRed.opacity(0.24), lineWidth: 1) }
                        }

                        Button {
                            Task { await importRecipe() }
                        } label: {
                            if isImporting {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Finding your recipe...")
                                }
                            } else {
                                Label("Import Recipe", systemImage: "link.badge.plus")
                            }
                        }
                        .buttonStyle(DashboardPrimaryButtonStyle())
                        .disabled(isImporting || homeId == nil)
                    }
                    .padding(24)
                    .dashboardCard(cornerRadius: 28)
                }
                .padding(.horizontal, horizontalSizeClass == .compact ? 18 : 34)
                .padding(.top, horizontalSizeClass == .compact ? 22 : 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Import Recipe")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import Recipe")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text("Add a recipe from a public URL.")
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private func importRecipe() async {
        guard !isImporting else { return }
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidRecipeURL(trimmedURL) else {
            errorMessage = "Enter a valid recipe URL."
            return
        }

        guard let homeId else {
            errorMessage = "Choose a Home before importing a recipe."
            return
        }

        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let response = try await service.importRecipe(homeId: homeId, url: trimmedURL)
            onImported(response)
        } catch let error as RecipeImportAPIError {
            errorMessage = error.userFacingMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isValidRecipeURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        return true
    }
}

#Preview("Import Recipe URL") {
    NavigationStack {
        ImportRecipeURLView(homeId: UUID()) { _ in }
    }
}
