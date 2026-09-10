//
//  Homey_iPhoneApp.swift
//  Homey-iPhone
//
//  Created by Johnny Laroco on 9/8/26.
//

import SwiftUI

@main
struct Homey_iPhoneApp: App {
    @StateObject private var appSession = AppSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSession)
        }
    }
}
