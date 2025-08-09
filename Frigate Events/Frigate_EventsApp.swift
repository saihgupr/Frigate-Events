//
//  Frigate_EventsApp.swift
//  Frigate Events
//
//  Created by Chris LaPointe on 7/24/25.
//

import SwiftUI
import UserNotifications

@main
struct Frigate_EventsApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @State private var showSettingsOnLaunch = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsStore)
                .onAppear {
                    if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
                        showSettingsOnLaunch = true
                        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                    }
                    requestNotificationAuthorization()
                }
                .sheet(isPresented: $showSettingsOnLaunch) {
                    SettingsView()
                        .environmentObject(settingsStore)
                }
        }
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission denied: \(error.localizedDescription)")
            }
        }
    }
}
