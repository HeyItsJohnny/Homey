import SwiftUI

struct CreateHomeView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var homeName = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var alertMessage: String?
    @FocusState private var focusedField: CreateHomeField?

    private let timezoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            AuthenticationBackground()

            if isRegularWidth {
                regularLayout
            } else {
                compactLayout
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Layouts

    private var regularLayout: some View {
        ScrollView {
            HStack(alignment: .center, spacing: 76) {
                AuthenticationHeroView(isCompact: false)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                AuthenticationFormCard {
                    createHomeForm
                }
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 1400)
            .padding(.horizontal, 56)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 720)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 22) {
                AuthenticationHeroView(isCompact: true)

                AuthenticationFormCard(isCompact: true) {
                    createHomeForm
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Form

    private var createHomeForm: some View {
        VStack(spacing: 20) {
            AuthenticationFormHeader(
                title: "Create Home",
                subtitle: "Create your family's Home to begin organizing meals, calendars, groceries, chores, and everything that keeps your household running."
            )

            VStack(spacing: 14) {
                AuthenticationTextField(
                    title: "The Smith Family",
                    systemImage: "house",
                    text: $homeName,
                    focusedField: $focusedField,
                    field: .homeName,
                    textContentType: nil,
                    textInputAutocapitalization: .words,
                    isAutocorrectionDisabled: false,
                    submitLabel: .done
                )

                AuthenticationPickerField(
                    title: "Timezone",
                    systemImage: "globe",
                    selection: $timezone,
                    options: timezoneIdentifiers,
                    label: { $0 }
                )
            }

            if let alertMessage {
                AuthenticationErrorView(message: alertMessage)
            }

            if let errorMessage = homeService.errorMessage,
               errorMessage != alertMessage {
                AuthenticationErrorView(message: errorMessage)
            }

            Button {
                Task {
                    await createHome()
                }
            } label: {
                if homeService.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Create Home")
                }
            }
            .buttonStyle(AuthenticationPrimaryButtonStyle())
            .disabled(homeService.isLoading)
        }
    }

    // MARK: - Actions

    private func createHome() async {
        alertMessage = nil

        guard let userID = authenticationService.currentUser?.id else {
            alertMessage = "No authenticated user was found."
            return
        }

        let didCreate = await homeService.createHome(
            name: homeName,
            timezone: timezone,
            userID: userID
        )

        if didCreate {
            dismiss()
        } else {
            alertMessage = homeService.errorMessage ?? "Unable to create Home."
        }
    }
}

private enum CreateHomeField: Hashable {
    case homeName
}

#Preview("iPhone Create Home") {
    NavigationStack {
        CreateHomeView()
            .environmentObject(AuthenticationService())
            .environmentObject(HomeService())
    }
}

#Preview("iPad Create Home") {
    NavigationStack {
        CreateHomeView()
            .environmentObject(AuthenticationService())
            .environmentObject(HomeService())
    }
}
