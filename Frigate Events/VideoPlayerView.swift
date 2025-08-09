
import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    private var player: AVPlayer

    init(videoURL: URL) {
        self.videoURL = videoURL
        self.player = AVPlayer(url: videoURL)
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                do {
                    try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Failed to set audio session category. Error: \(error)")
                }
                player.play()
            }
            .onDisappear {
                player.pause()
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                } catch {
                    print("Failed to deactivate audio session. Error: \(error)")
                }
            }
            .edgesIgnoringSafeArea(.all)
    }
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        if let url = URL(string: "http://devimages.apple.com/samplecode/adp/adp-60fps.mov") {
            VideoPlayerView(videoURL: url)
        } else {
            Text("Invalid URL for preview")
        }
    }
}
