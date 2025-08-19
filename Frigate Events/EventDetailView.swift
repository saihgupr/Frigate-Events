
import SwiftUI
import AVKit

struct EventDetailView: View {
    let event: FrigateEvent
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showingVideoPlayerSheet = false
    @State private var showingSnapshotSheet = false

    private var scoreFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
    }
    
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let fullSizeSnapshotUrl = event.fullSizeSnapshotUrl(baseURL: settingsStore.frigateBaseURL) {
                    Button(action: {
                        showingSnapshotSheet = true
                    }) {
                        RemoteImage(url: fullSizeSnapshotUrl) {
                            ProgressView()
                        } content: { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(10)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if event.has_clip {
                    Button(action: {
                        showingVideoPlayerSheet = true
                    }) {
                        Label("Play Clip", systemImage: "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    // Debug button for Frigate 15 compatibility
                    Button(action: {
                        Task {
                            let apiClient = FrigateAPIClient(baseURL: settingsStore.frigateBaseURL)
                            await apiClient.debugVideoAccess(eventId: event.id)
                        }
                    }) {
                        Label("Debug Video URLs", systemImage: "ladybug")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    
                    // Test specific video URL
                    Button(action: {
                        Task {
                            let apiClient = FrigateAPIClient(baseURL: settingsStore.frigateBaseURL)
                            await apiClient.testSpecificVideoURL(eventId: event.id)
                        }
                    }) {
                        Label("Test Video URL", systemImage: "video")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    // Test server connectivity
                    Button(action: {
                        Task {
                            let apiClient = FrigateAPIClient(baseURL: settingsStore.frigateBaseURL)
                            await apiClient.testServerConnectivity()
                        }
                    }) {
                        Label("Test Server", systemImage: "network")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }

                Text("\(event.friendlyLabelName)")
                    .font(.title2)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(event.friendlyCameraName)")
                    .font(.title3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("Start Time: \(Date(timeIntervalSince1970: event.start_time), formatter: itemFormatter)")
                    .foregroundColor(.white)
                    .font(.callout)
                    
                if let duration = event.duration {
                    Text("Duration: \(durationFormatter.string(from: duration) ?? "")")
                        .foregroundColor(.white)
                        .font(.callout)
                } else {
                    Text("End Time: In Progress")
                        .foregroundColor(.white)
                        .font(.callout)
                }

                if !event.zones.isEmpty {
                    Text("Zones: \(event.friendlyZoneNames)")
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.callout)
                }
                Text("Has Clip: \(event.has_clip ? "Yes" : "No")")
                    .foregroundColor(.white)
                    .font(.callout)
                Text("Has Snapshot: \(event.has_snapshot ? "Yes" : "No")")
                    .foregroundColor(.white)
                    .font(.callout)
                    
                
                if let falsePositive = event.false_positive {
                    Text("False Positive: \(falsePositive ? "Yes" : "No")")
                        .foregroundColor(.white)
                        .font(.callout)
                }
                
                if let plusId = event.plus_id {
                    Text("Plus ID: \(plusId)")
                        .foregroundColor(.white)
                        .font(.callout)
                }
                
                Text("Retain Indefinitely: \(event.retain_indefinitely ? "Yes" : "No")")
                    .foregroundColor(.white)
                    .font(.callout)
                
                if let subLabel = event.sub_label {
                    Text("Sub Label: \(subLabel)")
                        .foregroundColor(.white)
                        .font(.callout)
                }

                // You can add more details from the 'data' object here if needed
                if let eventData = event.data {
                    Divider().background(Color.gray)
                    Text("Detection Details:")
                        .font(.headline)
                        .foregroundColor(.white)
                        
                    Text("Type: \(eventData.type)")
                        .foregroundColor(.white)
                        .font(.body)
                    Text("Score: \(scoreFormatter.string(from: NSNumber(value: eventData.score)) ?? "")")
                        .foregroundColor(.white)
                        .font(.body)
                    Text("Top Score: \(scoreFormatter.string(from: NSNumber(value: eventData.top_score)) ?? "")")
                        .foregroundColor(.white)
                        .font(.body)
                    if !eventData.attributes.isEmpty {
                        Text("Attributes: \(eventData.attributes.joined(separator: ", "))")
                            .foregroundColor(.white)
                            .font(.body)
                    }
                    Text("Box: [\(eventData.box.map { String(format: "%.2f", $0) }.joined(separator: ", "))]")
                        .foregroundColor(.white)
                        .font(.body)
                    Text("Region: [\(eventData.region.map { String(format: "%.2f", $0) }.joined(separator: ", "))]")
                        .foregroundColor(.white)
                        .font(.body)
            }
            }
            .padding()
            #if !targetEnvironment(macCatalyst)
.navigationTitle("Event Details")
#endif
            .foregroundColor(.white) // Set navigation title color
            .background(Color.black)
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingVideoPlayerSheet) {
            if let clipUrl = event.clipUrl(baseURL: settingsStore.frigateBaseURL) {
                VideoPlayerView(
                    videoURL: clipUrl,
                    event: event,
                    baseURL: settingsStore.frigateBaseURL
                )
            } else {
                Text("Video not available.")
                    .foregroundColor(.white)
            }
        }
        .sheet(isPresented: $showingSnapshotSheet) {
            if let fullSizeSnapshotUrl = event.fullSizeSnapshotUrl(baseURL: settingsStore.frigateBaseURL) {
                SnapshotView(imageUrl: fullSizeSnapshotUrl)
            } else {
                Text("Snapshot not available.")
                    .foregroundColor(.white)
            }
        }
    }

    private let itemFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

struct EventDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EventDetailView(event: FrigateEvent(
            id: "12345.6789-test",
            camera: "front_door",
            label: "person",
            start_time: Date().timeIntervalSince1970 - 3600,
            end_time: Date().timeIntervalSince1970,
            has_clip: true,
            has_snapshot: true,
            zones: ["porch", "driveway"],
            data: EventData(
                attributes: [],
                box: [0.1, 0.2, 0.3, 0.4],
                region: [0.0, 0.0, 1.0, 1.0],
                score: 0.95,
                top_score: 0.98,
                type: "object"
            ),
            box: nil,
            false_positive: nil,
            plus_id: nil,
            retain_indefinitely: false,
            sub_label: nil,
            top_score: nil
        ))
    }
}
