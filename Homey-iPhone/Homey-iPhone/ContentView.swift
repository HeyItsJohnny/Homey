//
//  ContentView.swift
//  Homey-iPhone
//
//  Created by Johnny Laroco on 9/8/26.
//

import SwiftUI
struct ContentView: View {
    @EnvironmentObject private var appSession: AppSession
    var body: some View {
        Group {
            switch appSession.state {
            case .loading: LaunchView()
            case .unauthenticated: AuthenticationView()
            case .emailVerificationRequired:
                VerifyEmailView().safeAreaInset(edge: .bottom) {
                    Button("Back to Login") { appSession.returnToLogin() }.buttonStyle(HomeyButtonStyle()).padding()
                }
            case .resolvingAccount: AccountResolutionView(errorMessage: nil)
            case .accountResolutionFailed: AccountResolutionView(errorMessage: appSession.accountResolutionErrorMessage)
            case .pendingInvitations: PendingInvitationsOnboardingView()
            case .needsHome: CreateHomeView()
            case .selectingHome: HomeSelectionView()
            case .authenticated: MainTabView()
            }
        }
        .environmentObject(appSession.authentication)
        .environmentObject(appSession.homes)
        .task { if appSession.state == .loading { await appSession.launch() } }
        .overlay {
            if appSession.isSwitchingHome {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(HomeyColors.primary)
                        Text("Switching Home...")
                            .font(HomeyTypography.headline)
                            .foregroundStyle(HomeyColors.text)
                        Text("Loading the selected household and permissions.")
                            .font(.caption)
                            .foregroundStyle(HomeyColors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: 310)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.card))
                }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Switching Home")
            }
        }
        .animation(.easeInOut(duration: 0.18), value: appSession.isSwitchingHome)
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            HomeyBackground()
            VStack(spacing: 16) {
                Image(systemName: "house.fill").font(.largeTitle).foregroundStyle(HomeyColors.primary)
                ProgressView()
                Text("Opening Homey…").foregroundStyle(HomeyColors.secondaryText)
            }
        }
    }
}
