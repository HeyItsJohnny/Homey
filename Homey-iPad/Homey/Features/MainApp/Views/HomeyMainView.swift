import SwiftUI

struct HomeyMainView: View {
    var body: some View {
        HomeDashboardView()
    }
}

#Preview("Homey Main", traits: .landscapeLeft) {
    HomeyMainView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}
