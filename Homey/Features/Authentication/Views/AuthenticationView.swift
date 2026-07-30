import SwiftUI

struct AuthenticationView: View {
    @State private var destination: AuthenticationDestination = .login

    var body: some View {
        NavigationStack {
            switch destination {
            case .login:
                LoginView(
                    onCreateAccount: { destination = .signUp },
                    onForgotPassword: { destination = .forgotPassword }
                )
            case .signUp:
                SignUpView(
                    onBackToLogin: { destination = .login },
                    onVerificationRequired: { destination = .verifyEmail }
                )
            case .forgotPassword:
                ForgotPasswordView(
                    onBackToLogin: { destination = .login }
                )
            case .verifyEmail:
                VerifyEmailView(
                    onBackToLogin: { destination = .login }
                )
            }
        }
    }
}

private enum AuthenticationDestination {
    case login
    case signUp
    case forgotPassword
    case verifyEmail
}

#Preview {
    AuthenticationView()
        .environmentObject(AuthenticationService())
}
