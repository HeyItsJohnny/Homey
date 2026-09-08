//
//  HomeyApp.swift
//  Homey
//
//  Created by Johnny Laroco on 7/21/26.
//

import SwiftUI
import SwiftData

@main
struct HomeyApp: App {
    @StateObject private var authenticationService = AuthenticationService()
    @StateObject private var homeService = HomeService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authenticationService)
                .environmentObject(homeService)
        }
        .modelContainer(sharedModelContainer)
    }
}
