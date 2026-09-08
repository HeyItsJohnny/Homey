import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onBackToLogin: () -> Void
    let onVerificationRequired: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var displayName = ""
    @State private var isDisplayNameCustomized = false
    @State private var isUpdatingDisplayNameProgrammatically = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var validationMessage: String?
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @FocusState private var focusedField: SignUpField?

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
        .onChange(of: firstName) { _, _ in
            updateGeneratedDisplayNameIfNeeded()
        }
        .onChange(of: lastName) { _, _ in
            updateGeneratedDisplayNameIfNeeded()
        }
        .onChange(of: displayName) { _, newValue in
            handleDisplayNameChange(newValue)
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
                    signUpForm
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
                    signUpForm
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

    private var signUpForm: some View {
        VStack(spacing: 20) {
            AuthenticationFormHeader(
                title: "Create Account",
                subtitle: "Create your Homey account to get started."
            )

            VStack(spacing: 14) {
                AuthenticationTextField(
                    title: "First Name",
                    systemImage: "person",
                    text: $firstName,
                    focusedField: $focusedField,
                    field: .firstName,
                    textContentType: .givenName,
                    textInputAutocapitalization: .words,
                    isAutocorrectionDisabled: true,
                    submitLabel: .next
                )

                AuthenticationTextField(
                    title: "Last Name",
                    systemImage: "person",
                    text: $lastName,
                    focusedField: $focusedField,
                    field: .lastName,
                    textContentType: .familyName,
                    textInputAutocapitalization: .words,
                    isAutocorrectionDisabled: true,
                    submitLabel: .next
                )

                AuthenticationTextField(
                    title: "Display Name",
                    systemImage: "person.text.rectangle",
                    text: $displayName,
                    focusedField: $focusedField,
                    field: .displayName,
                    textContentType: .name,
                    textInputAutocapitalization: .words,
                    isAutocorrectionDisabled: true,
                    submitLabel: .next
                )

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
                    textContentType: .newPassword,
                    submitLabel: .next
                )

                AuthenticationSecureField(
                    title: "Confirm Password",
                    text: $confirmPassword,
                    isPasswordVisible: $isConfirmPasswordVisible,
                    focusedField: $focusedField,
                    field: .confirmPassword,
                    textContentType: .newPassword,
                    submitLabel: .go
                )
            }

            if let validationMessage {
                AuthenticationErrorView(message: validationMessage)
            }

            if let errorMessage = authenticationService.errorMessage {
                AuthenticationErrorView(message: errorMessage)
            }

            Button {
                Task {
                    await createAccount()
                }
            } label: {
                if authenticationService.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Create Account")
                }
            }
            .buttonStyle(AuthenticationPrimaryButtonStyle())
            .disabled(authenticationService.isLoading)

            AuthenticationDividerWithText(text: "or")

            Button("Back to Login", action: onBackToLogin)
                .buttonStyle(AuthenticationSecondaryButtonStyle())
        }
    }

    // MARK: - Actions

    private func createAccount() async {
        validationMessage = nil

        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedFirstName.isEmpty else {
            validationMessage = "Enter your first name."
            return
        }

        guard !trimmedLastName.isEmpty else {
            validationMessage = "Enter your last name."
            return
        }

        guard !trimmedDisplayName.isEmpty else {
            validationMessage = "Enter a display name."
            return
        }

        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "Enter your email address."
            return
        }

        guard !password.isEmpty else {
            validationMessage = "Enter a password."
            return
        }

        guard password == confirmPassword else {
            validationMessage = "Passwords do not match."
            return
        }

        await authenticationService.signUp(
            email: email,
            password: password,
            firstName: trimmedFirstName,
            lastName: trimmedLastName,
            displayName: trimmedDisplayName
        )

        if authenticationService.authenticationState == .emailVerificationRequired {
            onVerificationRequired()
        }
    }

    private func updateGeneratedDisplayNameIfNeeded() {
        guard !isDisplayNameCustomized else {
            return
        }

        setDisplayNameProgrammatically(
            ProfileNameFormatter.generatedDisplayName(firstName: firstName, lastName: lastName)
        )
    }

    private func handleDisplayNameChange(_ newValue: String) {
        guard !isUpdatingDisplayNameProgrammatically else {
            return
        }

        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isDisplayNameCustomized = false
            updateGeneratedDisplayNameIfNeeded()
            return
        }

        let generatedValue = ProfileNameFormatter.generatedDisplayName(firstName: firstName, lastName: lastName)
        isDisplayNameCustomized = newValue.trimmingCharacters(in: .whitespacesAndNewlines) != generatedValue
    }

    private func setDisplayNameProgrammatically(_ value: String) {
        isUpdatingDisplayNameProgrammatically = true
        displayName = value
        isUpdatingDisplayNameProgrammatically = false
    }
}

private enum SignUpField: Hashable {
    case firstName
    case lastName
    case displayName
    case email
    case password
    case confirmPassword
}

#Preview("iPhone Create Account") {
    NavigationStack {
        SignUpView(onBackToLogin: {}, onVerificationRequired: {})
            .environmentObject(AuthenticationService())
    }
}

#Preview("iPad Create Account") {
    NavigationStack {
        SignUpView(onBackToLogin: {}, onVerificationRequired: {})
            .environmentObject(AuthenticationService())
    }
}
