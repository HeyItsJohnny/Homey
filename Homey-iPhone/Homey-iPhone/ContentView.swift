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
            case .needsHome: CreateHomeView()
            case .selectingHome: HomeSelectionView()
            case .authenticated: MainTabView()
            }
        }
        .environmentObject(appSession.authentication)
        .environmentObject(appSession.homes)
        .task { if appSession.state == .loading { await appSession.launch() } }
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
