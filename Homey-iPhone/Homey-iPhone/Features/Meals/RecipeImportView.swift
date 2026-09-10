import SwiftUI

struct RecipeImportView: View {
    let home: HomeSummary
    let onPreview: (RecipeDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var loading = false
    @State private var error: String?
    @FocusState private var urlFocused: Bool
    private let service = MealsService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "link").font(.title).foregroundStyle(HomeyColors.recipeGreenAccent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import from Website").font(HomeyTypography.title)
                        Text("Paste a recipe link and Homey will fill in the details for you.")
                            .font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recipe URL").font(.subheadline.weight(.semibold))
                        HStack {
                            TextField("https://example.com/recipe", text: $url)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .keyboardType(.URL).textContentType(.URL).focused($urlFocused).submitLabel(.go)
                                .onSubmit { if RecipeImportInput.validURL(url) != nil { Task { await preview() } } }
                            if !url.isEmpty {
                                Button { url = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(HomeyColors.secondaryText) }
                                    .accessibilityLabel("Clear URL")
                            }
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if let error { HomeyErrorView(message: error) }
                    Button { Task { await preview() } } label: {
                        HStack(spacing: 10) {
                            if loading { ProgressView().tint(.white) }
                            Text(loading ? "Importing…" : "Import Recipe").font(.headline)
                        }.frame(maxWidth: .infinity).frame(minHeight: 54)
                            .foregroundStyle(.white).background(HomeyColors.recipeGreenAccent, in: Capsule())
                            .opacity(RecipeImportInput.validURL(url) == nil || loading ? 0.5 : 1)
                    }.disabled(RecipeImportInput.validURL(url) == nil || loading)
                }.padding(24).disabled(loading)
            }.scrollDismissesKeyboard(.interactively)
                .background(HomeyColors.recipeBackground.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(loading) }
                }
                .tint(HomeyColors.recipeGreenAccent)
                .interactiveDismissDisabled(loading)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func preview() async {
        guard !loading, let cleanURL = RecipeImportInput.validURL(url) else { return }
        urlFocused = false
        url = cleanURL
        loading = true
        error = nil
        defer { loading = false }
        do {
            let response = try await service.importURL(cleanURL, homeId: home.id)
            var draft = RecipeDraft()
            draft.apply(response)
            RecipeImportDiagnostics.mapped(draft)
            onPreview(draft)
        } catch { self.error = error.localizedDescription }
    }
}
