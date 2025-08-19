
import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    let event: FrigateEvent
    let baseURL: String
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var currentURLIndex = 0
    @State private var debugInfo: [String] = []
    @State private var hasTriedAllFormats = false

    init(videoURL: URL, event: FrigateEvent, baseURL: String) {
        self.videoURL = videoURL
        self.event = event
        self.baseURL = baseURL
    }

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        setupAudioSession()
                        player.play()
                        print("🎬 Video player started playing")
                    }
                    .onDisappear {
                        player.pause()
                        cleanupAudioSession()
                    }
                    .edgesIgnoringSafeArea(.all)
            } else if isLoading {
                VStack {
                    ProgressView("Loading video...")
                        .foregroundColor(.white)
                    Text("Trying URL format \(currentURLIndex + 1) of 4")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("URL: \(getCurrentURL()?.absoluteString ?? "Unknown")")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding()
                        .multilineTextAlignment(.center)
                    
                    // Debug info
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(debugInfo, id: \.self) { info in
                                Text(info)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 100)
                }
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Failed to load video")
                        .font(.headline)
                        .foregroundColor(.white)
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    // Debug info
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(debugInfo, id: \.self) { info in
                                Text(info)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 100)
                    
                    if !hasTriedAllFormats {
                        Button("Try Next Format") {
                            tryNextURL()
                        }
                        .foregroundColor(.blue)
                        .padding()
                    } else {
                        Button("Try All Formats Again") {
                            hasTriedAllFormats = false
                            currentURLIndex = 0
                            loadVideo()
                        }
                        .foregroundColor(.purple)
                        .padding()
                    }
                    
                    Button("Retry Current") {
                        loadVideo()
                    }
                    .foregroundColor(.green)
                    .padding()
                    
                    Button("Test All URLs") {
                        testAllURLFormats()
                    }
                    .foregroundColor(.yellow)
                    .padding()
                }
            }
        }
        .onAppear {
            print("🎬 VideoPlayerView appeared for event: \(event.id)")
            loadVideo()
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Video Error"),
                message: Text(errorMessage ?? "Unknown error occurred"),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func getCurrentURL() -> URL? {
        switch currentURLIndex {
        case 0:
            return event.clipUrl(baseURL: baseURL)
        case 1:
            return event.clipUrlAlternative1(baseURL: baseURL)
        case 2:
            return event.clipUrlAlternative2(baseURL: baseURL)
        case 3:
            return event.clipUrlAlternative3(baseURL: baseURL)
        default:
            return nil
        }
    }
    
    private func tryNextURL() {
        currentURLIndex = (currentURLIndex + 1) % 4
        if currentURLIndex == 0 {
            hasTriedAllFormats = true
        }
        loadVideo()
    }
    
    private func testAllURLFormats() {
        addDebugInfo("🧪 Testing all URL formats...")
        
        let urls = [
            ("Format 1", event.clipUrl(baseURL: baseURL)),
            ("Format 2", event.clipUrlAlternative1(baseURL: baseURL)),
            ("Format 3", event.clipUrlAlternative2(baseURL: baseURL)),
            ("Format 4", event.clipUrlAlternative3(baseURL: baseURL))
        ]
        
        for (index, (name, url)) in urls.enumerated() {
            guard let url = url else {
                addDebugInfo("❌ \(name): Invalid URL")
                continue
            }
            
            addDebugInfo("🔍 \(name): \(url.absoluteString)")
            
            // Test each URL
            testSingleURL(url) { success, error in
                DispatchQueue.main.async {
                    if success {
                        addDebugInfo("✅ \(name): SUCCESS")
                    } else {
                        addDebugInfo("❌ \(name): \(error ?? "Unknown error")")
                    }
                }
            }
        }
    }
    
    private func testSingleURL(_ url: URL, completion: @escaping (Bool, String?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, "Network error: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, "Invalid response")
                return
            }
            
            let statusCode = httpResponse.statusCode
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "Unknown"
            
            if statusCode == 200 && (contentType.contains("video/") || contentType.contains("application/octet-stream")) {
                completion(true, nil)
            } else {
                completion(false, "HTTP \(statusCode) - \(contentType)")
            }
        }.resume()
    }
    
    private func loadVideo() {
        guard let url = getCurrentURL() else {
            errorMessage = "No valid URL found"
            isLoading = false
            addDebugInfo("❌ No valid URL found for index \(currentURLIndex)")
            return
        }
        
        isLoading = true
        errorMessage = nil
        debugInfo.removeAll()
        
        addDebugInfo("🔄 Trying video URL: \(url.absoluteString)")
        print("🎬 Trying video URL: \(url.absoluteString)")
        
        // First, let's test if the URL is accessible
        testVideoURL(url: url) { success, error in
            DispatchQueue.main.async {
                if success {
                    addDebugInfo("✅ URL test successful")
                    // Create the player
                    let newPlayer = AVPlayer(url: url)
                    
                    // Add observer for player status
                    newPlayer.currentItem?.addObserver(
                        NSObject(),
                        forKeyPath: "status",
                        options: [.new, .old],
                        context: nil
                    )
                    
                    // Add periodic time observer to detect playback issues
                    let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                    newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                        // This will help us detect if the video is actually playing
                    }
                    
                    self.player = newPlayer
                    self.isLoading = false
                    addDebugInfo("✅ Video player created successfully")
                } else {
                    self.errorMessage = error ?? "Failed to access video URL"
                    self.isLoading = false
                    self.showError = true
                    addDebugInfo("❌ URL test failed: \(error ?? "Unknown error")")
                    
                    // Automatically try next URL if this one failed
                    if !self.hasTriedAllFormats {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.tryNextURL()
                        }
                    }
                }
            }
        }
    }
    
    private func addDebugInfo(_ message: String) {
        debugInfo.append(message)
        print("🎬 Debug: \(message)")
    }
    
    private func testVideoURL(url: URL, completion: @escaping (Bool, String?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD" // Just check headers, don't download content
        
        addDebugInfo("🔍 Testing URL with HEAD request...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                addDebugInfo("❌ Network error: \(error.localizedDescription)")
                completion(false, "Network error: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                addDebugInfo("❌ Invalid response")
                completion(false, "Invalid response")
                return
            }
            
            let statusCode = httpResponse.statusCode
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "Unknown"
            let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "Unknown"
            
            addDebugInfo("📊 Response: HTTP \(statusCode)")
            addDebugInfo("📊 Content-Type: \(contentType)")
            addDebugInfo("📊 Content-Length: \(contentLength)")
            
            print("🎬 Video URL Response: \(statusCode)")
            print("🎬 Content-Type: \(contentType)")
            print("🎬 Content-Length: \(contentLength)")
            
            if statusCode == 200 {
                if contentType.contains("video/") || contentType.contains("application/octet-stream") {
                    addDebugInfo("✅ Valid video content type")
                    completion(true, nil)
                } else {
                    addDebugInfo("❌ Invalid content type: \(contentType)")
                    completion(false, "Invalid content type: \(contentType)")
                }
            } else if statusCode == 401 {
                addDebugInfo("❌ Authentication required (HTTP 401)")
                completion(false, "Authentication required (HTTP 401)")
            } else if statusCode == 403 {
                addDebugInfo("❌ Access forbidden (HTTP 403)")
                completion(false, "Access forbidden (HTTP 403)")
            } else if statusCode == 404 {
                addDebugInfo("❌ Video not found (HTTP 404)")
                completion(false, "Video not found (HTTP 404)")
            } else {
                addDebugInfo("❌ HTTP \(statusCode)")
                completion(false, "HTTP \(statusCode)")
            }
        }.resume()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category. Error: \(error)")
        }
    }
    
    private func cleanupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session. Error: \(error)")
        }
    }
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        if let url = URL(string: "http://devimages.apple.com/samplecode/adp/adp-60fps.mov") {
            VideoPlayerView(
                videoURL: url,
                event: FrigateEvent(
                    id: "test",
                    camera: "test",
                    label: "test",
                    start_time: Date().timeIntervalSince1970,
                    end_time: Date().timeIntervalSince1970,
                    has_clip: true,
                    has_snapshot: true,
                    zones: [],
                    data: nil,
                    box: nil,
                    false_positive: nil,
                    plus_id: nil,
                    retain_indefinitely: false,
                    sub_label: nil,
                    top_score: nil
                ),
                baseURL: "http://test.com"
            )
        } else {
            Text("Invalid URL for preview")
        }
    }
}
