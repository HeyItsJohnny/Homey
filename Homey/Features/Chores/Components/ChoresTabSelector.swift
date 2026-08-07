import SwiftUI

struct ChoresTabSelector: View {
    let tabs: [ChoresTab]
    @Binding var selectedTab: ChoresTab

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                Picker("Chores section", selection: $selectedTab) {
                    ForEach(tabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: pickerWidth(for: proxy.size.width))
                .frame(minWidth: proxy.size.width, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: 48)
        .accessibilityLabel("Chores section")
    }

    private func pickerWidth(for availableWidth: CGFloat) -> CGFloat {
        let mealsPickerWidth: CGFloat = 520
        let mealsSegmentWidth = mealsPickerWidth / 3

        guard tabs.count > 3 else {
            return min(availableWidth, mealsPickerWidth)
        }

        return CGFloat(tabs.count) * mealsSegmentWidth
    }
}
