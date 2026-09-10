import SwiftUI

private enum AuthRoute: Hashable { case signUp, forgotPassword }

struct AuthenticationView: View {
    @EnvironmentObject private var appSession: AppSession
    @State private var path: [AuthRoute] = []
    var body: some View {
        NavigationStack(path: $path) {
            LoginView(onCreateAccount: { path.append(.signUp) }, onForgotPassword: { path.append(.forgotPassword) })
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signUp: SignUpView()
                    case .forgotPassword: ForgotPasswordView()
                    }
                }
        }.tint(HomeyColors.primary)
    }
}

struct AuthScreen<Content: View>: View {
    let title: String; let subtitle: String; @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            HomeyBackground()
            ScrollView {
                VStack(spacing: HomeySpacing.large) {
                    HomeyBrandHeader(title: title, subtitle: subtitle)
                    content
                }.homeyCard().padding(.horizontal, 20).padding(.vertical, 28)
            }.scrollDismissesKeyboard(.interactively)
        }.navigationBarTitleDisplayMode(.inline)
    }
}

struct LoginView: View {
    @EnvironmentObject private var appSession: AppSession
    let onCreateAccount: () -> Void; let onForgotPassword: () -> Void
    @State private var email = ""; @State private var password = ""; @State private var reveal = false
    @FocusState private var focus: Field?; private enum Field { case email, password }
    var body: some View {
        AuthScreen(title: "Homey", subtitle: "Your family's home, organized.") {
            VStack(spacing: 14) {
                TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .password }.homeyTextField()
                Group { if reveal { TextField("Password", text: $password) } else { SecureField("Password", text: $password) } }.textContentType(.password).focused($focus, equals: .password).submitLabel(.go).onSubmit(login).homeyTextField().overlay(alignment: .trailing) { Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye").frame(width: 44, height: 44) }.padding(.trailing, 5) }
                Button("Forgot Password", action: onForgotPassword).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .trailing)
                if let error = appSession.authentication.errorMessage { HomeyErrorView(message: error) }
                Button(action: login) { if appSession.authentication.isLoading { ProgressView().tint(.white) } else { Text("Log In") } }.buttonStyle(HomeyButtonStyle()).disabled(appSession.authentication.isLoading)
                Button("Create Account", action: onCreateAccount).buttonStyle(HomeyButtonStyle(secondary: true))
            }
        }.onAppear { appSession.authentication.clearError() }
    }
    private func login() { Task { if await appSession.authentication.signIn(email: email, password: password) { await appSession.didAuthenticate() } } }
}

struct SignUpView: View {
    @EnvironmentObject private var appSession: AppSession
    @State private var firstName = ""; @State private var lastName = ""; @State private var displayName = ""; @State private var email = ""; @State private var password = ""; @State private var confirm = ""; @State private var localError: String?
    @FocusState private var focus: Int?
    var body: some View {
        AuthScreen(title: "Create Account", subtitle: "Create your Homey account to get started.") {
            VStack(spacing: 14) {
                field("First Name", $firstName, 0, .givenName, .words); field("Last Name", $lastName, 1, .familyName, .words); field("Display Name", $displayName, 2, .nickname, .words); field("Email", $email, 3, .username, .never)
                SecureField("Password", text: $password).textContentType(.newPassword).focused($focus, equals: 4).homeyTextField()
                SecureField("Confirm Password", text: $confirm).textContentType(.newPassword).focused($focus, equals: 5).homeyTextField()
                if let localError { HomeyErrorView(message: localError) }
                if let error = appSession.authentication.errorMessage { HomeyErrorView(message: error) }
                Button(action: create) { if appSession.authentication.isLoading { ProgressView().tint(.white) } else { Text("Create Account") } }.buttonStyle(HomeyButtonStyle()).disabled(appSession.authentication.isLoading)
            }
        }.onAppear { appSession.authentication.clearError() }.onChange(of: firstName) { _, _ in updateDisplayName() }.onChange(of: lastName) { _, _ in updateDisplayName() }
    }
    private func field(_ title: String, _ text: Binding<String>, _ index: Int, _ type: UITextContentType, _ caps: TextInputAutocapitalization) -> some View { TextField(title, text: text).textContentType(type).textInputAutocapitalization(caps).autocorrectionDisabled().focused($focus, equals: index).homeyTextField() }
    private func updateDisplayName() { if displayName.isEmpty || displayName == [firstName, lastName].dropLast().joined(separator: " ") { displayName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") } }
    private func create() {
        localError = nil; guard password == confirm else { localError = "Passwords do not match."; return }
        Task { if let result = await appSession.authentication.signUp(email: email, password: password, firstName: firstName, lastName: lastName, displayName: displayName) { switch result { case .signedIn: await appSession.didAuthenticate(); case .verificationRequired: appSession.requireEmailVerification() } } }
    }
}

struct ForgotPasswordView: View {
    @EnvironmentObject private var appSession: AppSession
    @State private var email = ""; @State private var sent = false
    var body: some View {
        AuthScreen(title: "Forgot Password", subtitle: "We'll send instructions to your email address.") {
            VStack(spacing: 16) {
                TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).homeyTextField()
                if let error = appSession.authentication.errorMessage { HomeyErrorView(message: error) }
                if sent { Label("Password reset email sent.", systemImage: "checkmark.circle.fill").foregroundStyle(HomeyColors.success) }
                Button("Reset Password") { Task { sent = await appSession.authentication.sendPasswordReset(email: email) } }.buttonStyle(HomeyButtonStyle()).disabled(appSession.authentication.isLoading)
            }
        }.onAppear { appSession.authentication.clearError() }
    }
}

struct VerifyEmailView: View {
    var body: some View { ZStack { HomeyBackground(); HomeyBrandHeader(title: "Check Your Email", subtitle: "Confirm your email address, then return to Homey and log in.").homeyCard().padding(20) } }
}
