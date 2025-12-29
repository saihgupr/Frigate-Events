import SwiftUI

struct EventCardView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    let event: FrigateEvent
    let isInProgress: Bool
    @State private var isExpanded = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Event Info (always visible)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        if let thumbnailUrl = event.thumbnailUrl(baseURL: settingsStore.frigateBaseURL) {
                            RemoteImage(url: thumbnailUrl) {
                                ProgressView()
                                    .frame(width: 100, height: 100)
                            } content: { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 100)
                                    .cornerRadius(8)
                            }
                        } else {
                            Image(systemName: "photo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 100)
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            if isInProgress {
                                Text("In Progress")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                            Text("\(event.friendlyLabelName)")
                                .font(.headline)
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(event.friendlyCameraName)")
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(Date(timeIntervalSince1970: event.start_time), formatter: itemFormatter)")
                                .font(.subheadline)
                            if let duration = event.duration {
                                Text("Duration: \(durationFormatter.string(from: duration) ?? "")")
                                    .font(.subheadline)
                            } else if isInProgress {
                                let currentDuration = Date().timeIntervalSince1970 - event.start_time
                                Text("Duration: \(durationFormatter.string(from: currentDuration) ?? "0s")")
                                    .font(.subheadline)
                            } else {
                                Text("Duration: N/A") // Fallback for unexpected cases
                                    .font(.subheadline)
                            }
                            if !event.zones.isEmpty {
                                Text("\(event.friendlyZoneNames)")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .font(.subheadline)
                            }
                        }
                        .foregroundColor(.white)
                        Spacer() // Pushes content to the left
                    }
                }
                
                // Video section - part of the same expanding container
                if isExpanded && event.has_clip {
                    VStack(spacing: 0) {
                        if let clipUrl = event.clipUrl(baseURL: settingsStore.frigateBaseURL) {
                            VideoPlayerView(
                                videoURL: clipUrl,
                                event: event,
                                baseURL: settingsStore.frigateBaseURL,
                                onDismiss: {
                                    // No dismiss button needed - just close on tap
                                }
                            )
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(8) // Same corner radius as snapshots
                            .padding(.top, 8) // Add top padding for breathing room
                            .transition(.slide) // Smooth sliding animation like source project
                        } else {
                            Text("Video not available.")
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(red: 25/255, green: 25/255, blue: 25/255))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isInProgress ? Color.red : Color.gray.opacity(0.3), lineWidth: isInProgress ? 2 : 1)
            )
            .shadow(radius: 5)
            .animation(.easeInOut(duration: 0.4), value: isExpanded) // Slightly longer, smoother animation
            
            
        }
        .onTapGesture {
            if event.has_clip {
                withAnimation(.easeInOut(duration: 0.4)) { // Slightly longer, smoother animation
                    isExpanded.toggle()
                }
            }
        }

    }

    private let itemFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none // Removed date
        formatter.timeStyle = .medium
        return formatter
    }()
    
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
        }()
    


}

struct EventCardView_Previews: PreviewProvider {
    static var previews: some View {
        EventCardView(event: FrigateEvent(
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
        ), isInProgress: false)
    }
}
