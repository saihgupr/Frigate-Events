import SwiftUI
import Foundation

struct ContentView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @StateObject private var apiClient: FrigateAPIClient
    @State private var showSettings = false

    init() {
        _apiClient = StateObject(wrappedValue: FrigateAPIClient(baseURL: "")) // Initialized with empty string, will be updated in .onAppear
    }

    @State private var events: [FrigateEvent] = []
    @State private var inProgressEvents: [FrigateEvent] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    // Timers for polling
    @State private var inProgressTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @State private var eventsTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // Filtered events based on the settings
    private func applyFilters(to events: [FrigateEvent]) -> [FrigateEvent] {
        let labelFiltered = settingsStore.selectedLabels.isEmpty ? events : events.filter { settingsStore.selectedLabels.contains($0.label) }
        
        let zoneFiltered = settingsStore.selectedZones.isEmpty ? labelFiltered : labelFiltered.filter { event in
            !event.zones.isEmpty && !Set(event.zones).isDisjoint(with: settingsStore.selectedZones)
        }
        
        let cameraFiltered = settingsStore.selectedCameras.isEmpty ? zoneFiltered : zoneFiltered.filter { settingsStore.selectedCameras.contains($0.camera) }
        
        return cameraFiltered
    }

    private var filteredEvents: [FrigateEvent] {
        applyFilters(to: events)
    }

    private var filteredInProgressEvents: [FrigateEvent] {
        applyFilters(to: inProgressEvents)
    }

    @ViewBuilder
    private var eventsListView: some View {
        VStack(spacing: 15) {
            ForEach(filteredInProgressEvents) { event in
                NavigationLink(destination: EventDetailView(event: event).environmentObject(settingsStore)) {
                    EventCardView(event: event, isInProgress: true)
                }
                .buttonStyle(.plain)
            }
            ForEach(filteredEvents) { event in
                NavigationLink(destination: EventDetailView(event: event).environmentObject(settingsStore)) {
                    EventCardView(event: event, isInProgress: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading events...")
                        .accentColor(.white)
                        .padding()
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 10) {
                        Text("Error: \(errorMessage)")
                            .font(.headline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()

                        Button("Retry") {
                            Task { await refreshEvents(showLoadingIndicator: true) }
                        }
                    }
                    .padding()
                } else {
                    if #available(iOS 15.0, macOS 12.0, *) {
                        ScrollView {
                            eventsListView
                        }
                        .refreshable {
                            await refreshEvents(showLoadingIndicator: false)
                        }
                    } else {
                        ScrollView {
                            eventsListView
                        }
                    }
                }
            }
            .background(Color.black)
            #if !targetEnvironment(macCatalyst)
.navigationTitle("Frigate Events")
#endif
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing:
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gear")
                }
            )
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(settingsStore)
            }
            .onReceive(inProgressTimer) { _ in
                Task {
                    // This is a polled update, so we want the refresh logic.
                    await fetchInProgressEvents(andRefresh: true)
                }
            }
            .onReceive(eventsTimer) { _ in
                Task {
                    await fetchFrigateEvents()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .autoRetryConnection)) { _ in
                Task {
                    print("🔄 Auto-retry triggered from notification")
                    await refreshEvents(showLoadingIndicator: false)
                }
            }
            .onAppear {
                Task { await refreshEvents(showLoadingIndicator: true) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func refreshEvents(showLoadingIndicator: Bool = false) async {
        if showLoadingIndicator {
            isLoading = true
        }
        errorMessage = nil
        apiClient.baseURL = settingsStore.frigateBaseURL
        
        // Add a 0.5-second delay to make the refresh indicator more visible
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        await fetchFrigateEvents()
        await fetchInProgressEvents(andRefresh: false)
        await fetchAvailableCameras() // Fetch available cameras
        if showLoadingIndicator {
            isLoading = false
        }
    }

    private func fetchFrigateEvents() async {
        do {
            let fetchedEvents = try await apiClient.fetchEvents()
            events = fetchedEvents
            updateAvailableFilters(from: fetchedEvents)
            // Clear any stored error time on successful fetch
            UserDefaults.standard.removeObject(forKey: "lastNetworkErrorTime")
        } catch {
            errorMessage = error.localizedDescription
            print("Error fetching events: \(error)")
            
            // Store the error time for auto-retry logic
            UserDefaults.standard.set(Date(), forKey: "lastNetworkErrorTime")
        }
    }

    private func fetchInProgressEvents(andRefresh: Bool = true) async {
        do {
            let previousInProgressIds = Set(inProgressEvents.map { $0.id })
            let currentInProgressEvents = try await apiClient.fetchEvents(inProgress: true)
            self.inProgressEvents = currentInProgressEvents
            
            // Also update filters from in-progress events
            updateAvailableFilters(from: currentInProgressEvents)

            if andRefresh {
                let currentInProgressIds = Set(currentInProgressEvents.map { $0.id })
                let finishedEventIds = previousInProgressIds.subtracting(currentInProgressIds)
                if !finishedEventIds.isEmpty {
                    print("🔄 In-progress event(s) finished: \(finishedEventIds). Refreshing main event list after a 1-second delay to allow Frigate to update.")
                    try? await Task.sleep(nanoseconds: 500_000_000) // 1-second delay
                    
                    // Refresh the main events list
                    await fetchFrigateEvents()
                    
                    // Check if the finished events now appear in the main list
                    let mainEventIds = Set(events.map { $0.id })
                    let missingEvents = finishedEventIds.subtracting(mainEventIds)
                    
                    if !missingEvents.isEmpty {
                        print("⚠️ Some finished events not yet in main list: \(missingEvents). Retrying after another 1 second...")
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // Additional 1-second delay
                        await fetchFrigateEvents()
                        
                        // Final check
                        let finalMainEventIds = Set(events.map { $0.id })
                        let stillMissing = finishedEventIds.subtracting(finalMainEventIds)
                        if !stillMissing.isEmpty {
                            print("⚠️ Events still missing after retry: \(stillMissing)")
                        } else {
                            print("✅ All finished events now appear in main list")
                        }
                    } else {
                        print("✅ All finished events successfully moved to main list")
                    }
                }
            }
        } catch {
            // Don't show an error for a background poll, just log it.
            print("Error fetching in-progress events: \(error.localizedDescription)")
            
            // Still store error time for auto-retry, but don't show UI error
            UserDefaults.standard.set(Date(), forKey: "lastNetworkErrorTime")
        }
    }

    private func updateAvailableFilters(from events: [FrigateEvent]) {
        // Update labels
        let allLabels = Set(events.map { $0.label })
        let currentLabels = Set(settingsStore.availableLabels)
        let newLabels = allLabels.union(currentLabels)
        if newLabels.count > currentLabels.count {
            settingsStore.availableLabels = newLabels.sorted()
        }

        // Update zones
        let allZones = Set(events.flatMap { $0.zones })
        let currentZones = Set(settingsStore.availableZones)
        let newZones = allZones.union(currentZones)
        if newZones.count > currentZones.count {
            settingsStore.availableZones = newZones.sorted()
        }
    }

    private func fetchAvailableCameras() async {
        do {
            let cameras = try await apiClient.fetchCameras()
            updateAvailableCameras(from: cameras)
        } catch {
            // Don't show an error for a background poll, just log it.
            print("Error fetching available cameras: \(error.localizedDescription)")
        }
    }

    private func updateAvailableCameras(from cameras: [String]) {
        let currentCameras = Set(settingsStore.availableCameras)
        let newCameras = Set(cameras).union(currentCameras)
        if newCameras.count > currentCameras.count {
            settingsStore.availableCameras = newCameras.sorted()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsStore())
}
