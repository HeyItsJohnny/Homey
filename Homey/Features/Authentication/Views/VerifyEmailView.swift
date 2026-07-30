import SwiftUI

struct VerifyEmailView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService

    let onBackToLogin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Check your email to verify your account.")
                .multilineTextAlignment(.center)

            if let errorMessage = authenticationService.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    await authenticationService.refreshSession()
                }
            } label: {
                if authenticationService.isLoading {
                    ProgressView()
                } else {
                    Text("Refresh Session")
                }
            }
            .disabled(authenticationService.isLoading)

            Button("Back to Login") {
                Task {
                    await authenticationService.signOut()
                    onBackToLogin()
                }
            }
        }
        .padding()
        .navigationTitle("Verify Email")
        .onAppear {
            authenticationService.clearError()
        }
    }
}

#Preview {
    NavigationStack {
        VerifyEmailView(onBackToLogin: {})
            .environmentObject(AuthenticationService())
    }
}
