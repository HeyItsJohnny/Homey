import SwiftUI

struct GroceriesView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = GroceriesViewModel()
    let isActive: Bool
    @State private var expandedItemIDs: Set<UUID> = []
    @State private var showAddItem = false
    @State private var editingItem: GroceryItemWithSources?
    @State private var clearConfirmation: GroceryClearConfirmation?

    var body: some View {
        ZStack {
            HomeyBackground()
            VStack(spacing: 12) {
                header
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: GroceryLoadKey(homeID: session.activeHome?.id, isActive: isActive)) {
            guard isActive else { return }
            expandedItemIDs.removeAll()
            if let home = session.activeHome { await model.load(homeID: home.id) }
        }
        .sheet(isPresented: $showAddItem) {
            if let home = session.activeHome {
                AddGroceryItemView(model: model, homeID: home.id)
            }
        }
        .sheet(item: $editingItem) { display in
            EditGroceryCategoryView(display: display, model: model)
        }
        .alert("Groceries", isPresented: .init(get: { model.noticeMessage != nil }, set: { if !$0 { model.noticeMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.noticeMessage ?? "") }
        .alert("Groceries", isPresented: .init(get: { model.errorMessage != nil && !model.isLoading }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .alert(item: $clearConfirmation) { confirmation in
            switch confirmation {
            case .checked:
                Alert(
                    title: Text("Clear Checked Items?"),
                    message: Text("This will remove all checked items from your grocery list."),
                    primaryButton: .cancel(),
                    secondaryButton: .destructive(Text("Clear Checked Items")) {
                        Task {
                            if await model.clearCheckedItems() { expandedItemIDs.formIntersection(Set(model.items.map(\.id))) }
                        }
                    }
                )
            case .all:
                Alert(
                    title: Text("Clear Grocery List?"),
                    message: Text("This will remove all items from your Home grocery list. Recipes and Meal Plans will not be affected."),
                    primaryButton: .cancel(),
                    secondaryButton: .destructive(Text("Clear List")) {
                        Task {
                            if await model.clearAllItems() { expandedItemIDs.removeAll() }
                        }
                    }
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Groceries").font(.title.bold()).foregroundStyle(HomeyColors.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Home Grocery List").font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
            }
            Spacer()
            Menu {
                Button("Clear Checked Items", systemImage: "checkmark.circle") { clearConfirmation = .checked }
                    .disabled(model.checkedItemCount == 0 || model.isClearing)
                Button("Clear Grocery List", systemImage: "trash", role: .destructive) { clearConfirmation = .all }
                    .disabled(model.items.isEmpty || model.isClearing)
            } label: {
                if model.isClearing {
                    ProgressView().tint(HomeyColors.recipeGreenAccent).frame(width: 42, height: 42)
                } else {
                    Image(systemName: "ellipsis.circle").font(.title2).foregroundStyle(HomeyColors.text)
                        .frame(width: 42, height: 42)
                }
            }
            .accessibilityLabel("Grocery list actions")
            .disabled(model.list == nil || model.isClearing)
            Button { showAddItem = true } label: {
                Label("Add Item", systemImage: "plus")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 42)
                    .background(HomeyColors.recipeGreenAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(session.activeHome == nil || model.list == nil)
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    @ViewBuilder private var content: some View {
        if session.activeHome == nil {
            ContentUnavailableView("Choose a Home", systemImage: "house")
        } else if model.isLoading && model.list == nil {
            Spacer()
            ProgressView("Loading groceries…").tint(HomeyColors.recipeGreenAccent)
            Spacer()
        } else if model.errorMessage != nil && model.list == nil {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(HomeyColors.recipeOrangeAccent)
                Text("Unable to load groceries.").font(HomeyTypography.headline)
                Button("Retry") {
                    guard let home = session.activeHome else { return }
                    Task { await model.load(homeID: home.id) }
                }.buttonStyle(.borderedProminent).tint(HomeyColors.recipeGreenAccent)
            }.padding(24).frame(maxWidth: .infinity).homeyCard().padding(20)
            Spacer()
        } else if model.items.isEmpty {
            Spacer()
            VStack(spacing: 15) {
                Image(systemName: "cart")
                    .font(.system(size: 34)).foregroundStyle(HomeyColors.recipeGreenAccent)
                    .frame(width: 76, height: 76).background(HomeyColors.recipeGreenAccent.opacity(0.1), in: Circle())
                Text("Your grocery list is empty").font(HomeyTypography.title)
                Text("Add items manually or send ingredients from Recipes and Meal Plan.")
                    .font(.subheadline).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.center)
                Button("Add Item") { showAddItem = true }
                    .buttonStyle(.borderedProminent).tint(HomeyColors.recipeGreenAccent)
            }
            .padding(28).frame(maxWidth: .infinity)
            .background(HomeyColors.recipeCardBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .brown.opacity(0.08), radius: 18, y: 8).padding(20)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(model.groupedItems, id: \.category.id) { group in
                        grocerySection(category: group.category, items: group.items)
                    }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 32)
            }
            .refreshable {
                if let home = session.activeHome { await model.load(homeID: home.id) }
            }
        }
    }

    private func grocerySection(category: GroceryCategory, items: [GroceryItemWithSources]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.rawValue.uppercased())
                .font(.caption.weight(.bold)).foregroundStyle(HomeyColors.secondaryText)
                .padding(.horizontal, 6)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, display in
                    if index > 0 { Divider().padding(.leading, 54) }
                    groceryRow(display)
                }
            }
            .background(HomeyColors.recipeCardBackground.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .brown.opacity(0.06), radius: 12, y: 5)
        }
    }

    private func groceryRow(_ display: GroceryItemWithSources) -> some View {
        let expanded = expandedItemIDs.contains(display.id)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { Task { await model.toggleChecked(display) } } label: {
                    Image(systemName: display.item.isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(display.item.isChecked ? HomeyColors.recipeGreenAccent : HomeyColors.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).disabled(model.mutatingItemIDs.contains(display.id))
                .accessibilityLabel("\(display.item.ingredientName), \(display.item.isChecked ? "checked" : "unchecked"), \(sourceCountLabel(display.sources.count))")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded { expandedItemIDs.remove(display.id) } else { expandedItemIDs.insert(display.id) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(display.item.ingredientName)
                            .font(.body.weight(.medium)).foregroundStyle(display.item.isChecked ? HomeyColors.secondaryText : HomeyColors.text)
                            .strikethrough(display.item.isChecked).frame(maxWidth: .infinity, alignment: .leading)
                        if !display.sources.isEmpty {
                            Text(sourceCountLabel(display.sources.count)).font(.caption).foregroundStyle(HomeyColors.secondaryText)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }.frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(display.item.ingredientName), \(sourceCountLabel(display.sources.count))")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityHint(expanded ? "Collapses source details" : "Expands source details")

                Menu {
                    Button("Edit", systemImage: "pencil") { editingItem = display }
                    Button("Delete Item", systemImage: "trash", role: .destructive) {
                        expandedItemIDs.remove(display.id)
                        Task { await model.delete(display) }
                    }
                } label: {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                        .foregroundStyle(HomeyColors.secondaryText).frame(width: 36, height: 44)
                }.accessibilityLabel("Actions for \(display.item.ingredientName)")
            }.padding(.horizontal, 8)

            if expanded {
                VStack(alignment: .leading, spacing: 9) {
                    Divider()
                    if display.sources.isEmpty {
                        Text("Manually added").font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                    } else {
                        Text("Needed for:").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
                        ForEach(display.sources) { source in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(HomeyColors.recipeGreenAccent).frame(width: 5, height: 5).padding(.top, 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.sourceLabel).font(.subheadline.weight(.medium)).foregroundStyle(HomeyColors.text)
                                    Text(sourceContext(source)).font(.caption).foregroundStyle(HomeyColors.secondaryText)
                                }
                            }
                        }
                    }
                }.padding(.leading, 54).padding(.trailing, 16).padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func sourceCountLabel(_ count: Int) -> String {
        count == 1 ? "1 source" : "\(count) sources"
    }

    private func sourceContext(_ source: GrocerySource) -> String {
        switch source.sourceType {
        case .homeRecipe: return "Home Recipe"
        case .mealEvent:
            guard let sourceDate = source.sourceDate,
                  let date = sourceDate.date(in: session.activeTimezone)
            else { return "Planned meal" }
            var style = Date.FormatStyle.dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
            style.timeZone = session.activeTimezone
            return date.formatted(style)
        }
    }
}

private enum GroceryClearConfirmation: String, Identifiable {
    case checked, all
    var id: String { rawValue }
}

private struct GroceryLoadKey: Hashable {
    let homeID: UUID?
    let isActive: Bool
}

private struct AddGroceryItemView: View {
    @ObservedObject var model: GroceriesViewModel
    let homeID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: GroceryCategory = .other
    @State private var lastSuggestion: GroceryCategory = .other
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Item Name").font(.caption.weight(.bold)).foregroundStyle(HomeyColors.secondaryText)
                    TextField("e.g. Milk", text: $name).homeyTextField().submitLabel(.done)
                        .onChange(of: name) {
                            let suggestion = GroceryCategoryMatcher.category(for: name)
                            if category == lastSuggestion { category = suggestion }
                            lastSuggestion = suggestion
                        }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category").font(.caption.weight(.bold)).foregroundStyle(HomeyColors.secondaryText)
                    Picker("Category", selection: $category) {
                        ForEach(GroceryCategory.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
                }
                Spacer()
                Button {
                    Task {
                        isSaving = true
                        let succeeded = await model.addManualItem(name: name, category: category, homeID: homeID)
                        isSaving = false
                        if succeeded { dismiss() }
                    }
                } label: {
                    HStack { if isSaving { ProgressView().tint(.white) }; Text(isSaving ? "Adding…" : "Add Item") }
                        .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                        .background(HomeyColors.recipeGreenAccent, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
                }.buttonStyle(.plain).disabled(GroceryNameNormalizer.normalize(name).isEmpty || isSaving)
                    .opacity(GroceryNameNormalizer.normalize(name).isEmpty ? 0.5 : 1)
            }.padding(20).background(HomeyColors.recipeBackground.ignoresSafeArea())
                .navigationTitle("Add Grocery Item").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) } }
        }.presentationDetents([.medium])
    }
}

private struct EditGroceryCategoryView: View {
    let display: GroceryItemWithSources
    @ObservedObject var model: GroceriesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var category: GroceryCategory
    @State private var name: String
    @State private var isSaving = false

    init(display: GroceryItemWithSources, model: GroceriesViewModel) {
        self.display = display; self.model = model
        _category = State(initialValue: display.item.category)
        _name = State(initialValue: display.item.ingredientName)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Item Name").font(.caption.weight(.bold)).foregroundStyle(HomeyColors.secondaryText)
                    TextField("Item Name", text: $name).homeyTextField().submitLabel(.done)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category").font(.caption.weight(.bold)).foregroundStyle(HomeyColors.secondaryText)
                    Picker("Category", selection: $category) {
                        ForEach(GroceryCategory.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
                }
                Spacer()
                Button {
                    Task {
                        isSaving = true
                        let succeeded = await model.update(display, name: name, category: category)
                        isSaving = false
                        if succeeded { dismiss() }
                    }
                } label: {
                    HStack { if isSaving { ProgressView().tint(.white) }; Text("Save Category") }
                        .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                        .background(HomeyColors.recipeGreenAccent, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
                }.buttonStyle(.plain).disabled(GroceryNameNormalizer.normalize(name).isEmpty || isSaving)
                    .opacity(GroceryNameNormalizer.normalize(name).isEmpty ? 0.5 : 1)
            }.padding(20).background(HomeyColors.recipeBackground.ignoresSafeArea())
                .navigationTitle("Edit Grocery Item").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) } }
        }.presentationDetents([.medium])
    }
}
