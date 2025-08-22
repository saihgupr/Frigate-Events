//
//  Frigate_EventsApp.swift
//  Frigate Events
//
//  Created by Chris LaPointe on 7/24/25.
//

import SwiftUI
import UserNotifications
import UIKit

extension Notification.Name {
    static let autoRetryConnection = Notification.Name("autoRetryConnection")
    static let refreshFromMenu = Notification.Name("refreshFromMenu")
}

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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Automatically retry when app becomes active
                    handleAppDidBecomeActive()
                }
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Refresh Events") {
                    NotificationCenter.default.post(name: .refreshFromMenu, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
    
    private func handleAppDidBecomeActive() {
        print("🔄 App became active - checking for auto-retry...")
        
        // Check if we should auto-retry based on last error time
        if let lastErrorTime = UserDefaults.standard.object(forKey: "lastNetworkErrorTime") as? Date {
            let timeSinceError = Date().timeIntervalSince(lastErrorTime)
            
            // Only auto-retry if the last error was within the last 5 minutes
            // This prevents excessive retries for persistent issues
            if timeSinceError < 300 { // 5 minutes
                print("🔄 Auto-retrying connection after app became active...")
                
                // Add a small delay to ensure the app is fully active
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: .autoRetryConnection, object: nil)
                }
            } else {
                print("🔄 Last error was \(Int(timeSinceError/60)) minutes ago - skipping auto-retry")
            }
        } else {
            print("🔄 No recent errors found - no auto-retry needed")
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
