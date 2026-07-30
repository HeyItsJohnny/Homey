import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onCreateAccount: () -> Void
    let onForgotPassword: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @FocusState private var focusedField: LoginField?

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
        .onAppear {
            authenticationService.clearError()
        }
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
                    loginForm
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
                    loginForm
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

    private var loginForm: some View {
        VStack(spacing: 20) {
            AuthenticationFormHeader(
                title: "Homey",
                subtitle: "Your family’s home, organized."
            )

            VStack(spacing: 14) {
                AuthenticationTextField(
                    title: "Email",
                    systemImage: "envelope",
                    text: $email,
                    focusedField: $focusedField,
                    field: .email,
                    keyboardType: .emailAddress,
                    textContentType: .username,
                    submitLabel: .next
                )

                AuthenticationSecureField(
                    title: "Password",
                    text: $password,
                    isPasswordVisible: $isPasswordVisible,
                    focusedField: $focusedField,
                    field: .password,
                    textContentType: .password,
                    submitLabel: .go
                )
            }

            Button("Forgot Password", action: onForgotPassword)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AuthenticationTheme.primaryBlue)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let errorMessage = authenticationService.errorMessage {
                AuthenticationErrorView(message: errorMessage)
            }

            Button {
                Task {
                    await authenticationService.signIn(email: email, password: password)
                }
            } label: {
                if authenticationService.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Sign In")
                }
            }
            .buttonStyle(AuthenticationPrimaryButtonStyle())
            .disabled(authenticationService.isLoading)

            AuthenticationDividerWithText(text: "or")

            Button(action: onCreateAccount) {
                Text("Create Account")
            }
            .buttonStyle(AuthenticationSecondaryButtonStyle())
        }
    }
}

private enum LoginField: Hashable {
    case email
    case password
}

#Preview("iPhone Login") {
    NavigationStack {
        LoginView(onCreateAccount: {}, onForgotPassword: {})
            .environmentObject(AuthenticationService())
    }
}

#Preview("iPad Login") {
    NavigationStack {
        LoginView(onCreateAccount: {}, onForgotPassword: {})
            .environmentObject(AuthenticationService())
    }
}
