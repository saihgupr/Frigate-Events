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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Track when app goes to background
                    UserDefaults.standard.set(Date(), forKey: "lastBackgroundTime")
                    print("🔄 App entered background at \(Date())")
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
        print("🔄 App became active - checking for auto-refresh...")
        
        // Get the last time the app was backgrounded and current time
        let lastBackgroundTime = UserDefaults.standard.object(forKey: "lastBackgroundTime") as? Date
        let currentTime = Date()
        
        // Check if we should auto-refresh
        var shouldRefresh = false
        
        if let lastErrorTime = UserDefaults.standard.object(forKey: "lastNetworkErrorTime") as? Date {
            let timeSinceError = currentTime.timeIntervalSince(lastErrorTime)
            print("🔄 Last error was \(Int(timeSinceError/60)) minutes ago")
            
            // If there was a recent error (within 24 hours), always refresh on app activation
            if timeSinceError < 86400 { // 24 hours
                shouldRefresh = true
                print("🔄 Recent error detected - will auto-refresh")
            }
        }
        
        // Also refresh if the app has been in background for more than 30 minutes
        if let backgroundTime = lastBackgroundTime {
            let timeSinceBackground = currentTime.timeIntervalSince(backgroundTime)
            if timeSinceBackground > 1800 { // 30 minutes
                shouldRefresh = true
                print("🔄 App was backgrounded for \(Int(timeSinceBackground/60)) minutes - will auto-refresh")
            }
        } else {
            // First launch or no background time recorded, refresh to be safe
            shouldRefresh = true
            print("🔄 No background time recorded - will auto-refresh")
        }
        
        // Prevent too frequent refreshes (not more than once every 30 seconds)
        let lastAutoRefreshTime = UserDefaults.standard.object(forKey: "lastAutoRefreshTime") as? Date
        if let lastRefresh = lastAutoRefreshTime {
            let timeSinceLastRefresh = currentTime.timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < 30 {
                shouldRefresh = false
                print("🔄 Auto-refresh was too recent (\(Int(timeSinceLastRefresh))s ago) - skipping")
            }
        }
        
        if shouldRefresh {
            print("🔄 Auto-refreshing after app became active...")
            UserDefaults.standard.set(currentTime, forKey: "lastAutoRefreshTime")
            
            // Add a small delay to ensure the app is fully active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .autoRetryConnection, object: nil)
            }
        } else {
            print("🔄 No auto-refresh needed")
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
