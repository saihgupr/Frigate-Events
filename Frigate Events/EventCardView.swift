
import SwiftUI
import AVKit

struct EventCardView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    let event: FrigateEvent
    let isInProgress: Bool
    @State private var isExpanded: Bool = false
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                // Event Info (always visible)
                HStack(alignment: .top, spacing: 8) {
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

                // Expandable Video Player
                if isExpanded && event.has_clip, let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(8)
                        .transition(.slide)
                        .onDisappear {
                            player.pause()
                            self.player = nil
                        }
                }
            }
            .padding(8)
            .background(Color.init(red: 0.1, green: 0.1, blue: 0.1))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isInProgress ? Color.red : Color.gray.opacity(0.3), lineWidth: isInProgress ? 2 : 1)
            )
            .shadow(radius: 5)
            
            
        }
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
                if isExpanded && event.has_clip, let clipUrl = event.clipUrl(baseURL: settingsStore.frigateBaseURL) {
                    self.player = AVPlayer(url: clipUrl)
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
                        try AVAudioSession.sharedInstance().setActive(true)
                    } catch {
                        print("Failed to set audio session category. Error: \(error)")
                    }
                    self.player?.play()
                } else {
                    self.player?.pause()
                    self.player = nil
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
