import SwiftUI
import AVKit

// Video manager with optimized downloads and preloading
class VideoManager {
    static let shared = VideoManager()

    private let tempPath: URL
    private var currentVideoURL: URL?
    private var downloadTasks: [URL: URLSessionDownloadTask] = [:]
    private var preloadedVideos: [String: URL] = [:] // eventId -> local URL
    private let maxPreloadedVideos = 3

    // Optimized URLSession for video downloads
    private lazy var videoSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 5
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: nil, delegateQueue: .main)
    }()

    init() {
        tempPath = FileManager.default.temporaryDirectory.appendingPathComponent("FrigateVideos")
        createTempDirectory()
        cleanupTempFiles() // Clean up any leftover files on startup
    }

    private func createTempDirectory() {
        do {
            try FileManager.default.createDirectory(at: tempPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ VideoManager: Failed to create temp directory: \(error.localizedDescription)")
        }
    }

    func cleanupTempFiles() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempPath, includingPropertiesForKeys: nil)
            for file in files {
                if file.pathExtension == "mp4" {
                    try FileManager.default.removeItem(at: tempPath.appendingPathComponent(file.lastPathComponent))
                    print("🗑️ VideoManager: Cleaned up temp file: \(file.lastPathComponent)")
                }
            }
        } catch {
            print("❌ VideoManager: Failed to cleanup temp files: \(error.localizedDescription)")
        }
    }

    func createTempVideoURL(for eventId: String) -> URL {
        // Clean up previous video if it exists
        if let currentVideoURL = currentVideoURL {
            try? FileManager.default.removeItem(at: currentVideoURL)
        }

        let videoFileName = "\(eventId)_temp.mp4"
        let tempVideoURL = tempPath.appendingPathComponent(videoFileName)
        currentVideoURL = tempVideoURL
        return tempVideoURL
    }

    func cleanupCurrentVideo() {
        if let currentVideoURL = currentVideoURL {
            do {
                try FileManager.default.removeItem(at: currentVideoURL)
                print("🗑️ VideoManager: Cleaned up current video: \(currentVideoURL.lastPathComponent)")
            } catch {
                print("❌ VideoManager: Failed to cleanup current video: \(error.localizedDescription)")
            }
            self.currentVideoURL = nil
        }
    }

    // Pre-load video in background for faster playback
    func preloadVideo(for eventId: String, from remoteURL: URL) {
        // Check if already preloaded
        if preloadedVideos[eventId] != nil {
            print("✅ VideoManager: Video already preloaded for event \(eventId)")
            return
        }

        // Cancel any existing download for this URL
        if let existingTask = downloadTasks[remoteURL] {
            existingTask.cancel()
            downloadTasks.removeValue(forKey: remoteURL)
        }

        // Clean up old preloaded videos if we have too many
        if preloadedVideos.count >= maxPreloadedVideos {
            let oldestEventId = preloadedVideos.keys.first!
            if let oldURL = preloadedVideos.removeValue(forKey: oldestEventId) {
                try? FileManager.default.removeItem(at: oldURL)
                print("🗑️ VideoManager: Cleaned up old preloaded video: \(oldestEventId)")
            }
        }

        let tempVideoURL = createTempVideoURL(for: "\(eventId)_preload")

        print("🚀 VideoManager: Starting background preload for event \(eventId)")

        let task = videoSession.downloadTask(with: remoteURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            self.downloadTasks.removeValue(forKey: remoteURL)

            if let error = error {
                print("❌ VideoManager: Preload failed for \(eventId): \(error.localizedDescription)")
                return
            }

            guard let tempURL = tempURL else {
                print("❌ VideoManager: No temp URL for preload \(eventId)")
                return
            }

            do {
                // Move downloaded file to our temp location
                try FileManager.default.moveItem(at: tempURL, to: tempVideoURL)
                self.preloadedVideos[eventId] = tempVideoURL
                print("✅ VideoManager: Successfully preloaded video for event \(eventId)")
            } catch {
                print("❌ VideoManager: Failed to save preloaded video: \(error.localizedDescription)")
            }
        }

        downloadTasks[remoteURL] = task
        task.resume()
    }

    // Check if video is preloaded and return local URL
    func getPreloadedVideo(for eventId: String) -> URL? {
        return preloadedVideos[eventId]
    }

    // Cancel all preloading tasks
    func cancelAllPreloads() {
        for task in downloadTasks.values {
            task.cancel()
        }
        downloadTasks.removeAll()
    }

    // Public accessors for preloading status
    func getPreloadedVideoCount() -> Int {
        return preloadedVideos.count
    }

    func getPreloadedEventIds() -> [String] {
        return Array(preloadedVideos.keys)
    }

    // Public accessor for video session
    var publicVideoSession: URLSession {
        return videoSession
    }

    func getStorageUsage() -> (fileCount: Int, totalSizeMB: Double) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempPath, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: Int64 = 0
            var fileCount = 0

            for url in files {
                if url.pathExtension == "mp4" {
                    fileCount += 1
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attributes[.size] as? Int64 {
                        totalSize += size
                    }
                }
            }

            let totalSizeMB = Double(totalSize) / (1024 * 1024)
            return (fileCount, totalSizeMB)
        } catch {
            return (0, 0.0)
        }
    }
}

// UIViewControllerRepresentable for AVPlayerViewController - more reliable than SwiftUI VideoPlayer
struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true  // Show controls for better UX
        controller.videoGravity = .resizeAspect  // Scale to fit screen

        // Configure for remote video playback
        if let playerItem = player.currentItem {
            // Add observers for debugging
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                print("🎬 VideoPlayer: Video played to end")
            }

            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { notification in
                if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                    print("🎬 VideoPlayer: Failed to play to end: \(error.localizedDescription)")
                }
            }

            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: playerItem,
                queue: .main
            ) { _ in
                print("🎬 VideoPlayer: Playback stalled")
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

struct VideoPlayerView: View {
    let videoURL: URL
    let event: FrigateEvent
    let baseURL: String
    var onDismiss: (() -> Void)? = nil
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentUrlIndex = 0
    @State private var hasTriedAllFormats = false

    init(videoURL: URL, event: FrigateEvent, baseURL: String, onDismiss: (() -> Void)? = nil) {
        self.videoURL = videoURL
        self.event = event
        self.baseURL = baseURL
        self.onDismiss = onDismiss
        print("🎬 VideoPlayerView: Initialized with URL: \(videoURL.absoluteString)")
        print("🎬 VideoPlayerView: Event ID: \(event.id)")
        print("🎬 VideoPlayerView: Has dismiss action: \(onDismiss != nil)")
    }

    // Get all video URLs like Android does - ultra simple
    private var videoUrls: [URL] {
        return [
            event.clipUrl(baseURL: baseURL),
            event.clipUrlAlternative1(baseURL: baseURL),
            event.clipUrlAlternative2(baseURL: baseURL),
            event.clipUrlAlternative3(baseURL: baseURL),
            event.clipUrlAlternative4(baseURL: baseURL),
            event.clipUrlAlternative5(baseURL: baseURL)
        ].compactMap { $0 }
    }

    private var currentVideoUrl: URL? {
        videoUrls.indices.contains(currentUrlIndex) ? videoUrls[currentUrlIndex] : nil
    }

    var body: some View {
        ZStack {
            if let player = player {
                AVPlayerViewControllerRepresentable(player: player)
                    .onAppear {
                        setupAudioSession()
                        player.play()
                        print("🎬 Video player started playing")
                    }
                    .onDisappear {
                        player.pause()
                        cleanupAudioSession()
                        VideoManager.shared.cleanupCurrentVideo() // Clean up temp files
                    }
                    .edgesIgnoringSafeArea(.all)
            } else {
                // Enhanced loading/error state with optimized download
                VStack(spacing: 16) {
                    if isLoading {
                        // Loading state - no text or progress indicators
                        Color.clear
                            .frame(height: 100)
                    } else if errorMessage != nil {
                        // Error state - no text or icons
                        Color.clear
                            .frame(height: 100)
                    } else {
                        // No video available state - no text or icons
                        Color.clear
                            .frame(height: 100)
                    }

                    // No buttons or text - completely clean interface
                    Color.clear
                        .frame(height: 50)
                }
                .onAppear {
                    print("🎬 VideoPlayerView appeared for event: \(event.id)")
                    print("🎬 VideoPlayerView: isLoading = \(isLoading)")
                    print("🎬 VideoPlayerView: errorMessage = \(errorMessage ?? "nil")")
                    Task { await downloadAndPlayVideo() }
                }
            }
        }
        .background(Color.black)
    }

    // Optimized video loading methods
    private func tryNextUrl() {
        currentUrlIndex = (currentUrlIndex + 1) % videoUrls.count
        if currentUrlIndex == 0 {
            hasTriedAllFormats = true
        }
        Task { await downloadAndPlayVideo() }
    }

    private func downloadAndPlayVideo() async {
        guard let videoUrl = currentVideoUrl else {
            errorMessage = "No video URL available"
            isLoading = false
            print("❌ VideoPlayer: No video URL available")
            return
        }

        print("📥 VideoPlayer: Starting optimized download from: \(videoUrl)")
        print("📥 VideoPlayer: Current URL index: \(currentUrlIndex)")
        print("📥 VideoPlayer: Total URLs available: \(videoUrls.count)")

        isLoading = true
        errorMessage = nil

        do {
            // Check if video is already preloaded
            if let preloadedURL = VideoManager.shared.getPreloadedVideo(for: event.id) {
                print("🎯 VideoPlayer: Using preloaded video for \(event.id)")
                playLocalVideo(from: preloadedURL)
                return
            }

            // Create temp file URL
            let tempVideoURL = VideoManager.shared.createTempVideoURL(for: event.id)

            // Create optimized request with better headers
            var request = URLRequest(url: videoUrl)
            request.httpMethod = "GET"
            request.setValue("FrigateEventsiOS/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("video/mp4, video/*, */*", forHTTPHeaderField: "Accept")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
            request.setValue("bytes=0-", forHTTPHeaderField: "Range") // Support for partial content

            print("🚀 VideoPlayer: Starting optimized download with custom headers")

            // Use optimized session for download
            let (data, response) = try await VideoManager.shared.publicVideoSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
                print("❌ VideoPlayer: HTTP \(httpResponse.statusCode) - \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))")
                throw URLError(.badServerResponse)
            }

            // Save to temp directory
            try data.write(to: tempVideoURL)
            let fileSizeMB = Double(data.count) / (1024 * 1024)
            print("💾 VideoPlayer: Downloaded \(String(format: "%.1f", fileSizeMB))MB video")

            // Play the downloaded video
            playLocalVideo(from: tempVideoURL)

        } catch {
            print("❌ VideoPlayer: Download failed: \(error.localizedDescription)")
            errorMessage = "Download failed: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func playLocalVideo(from localURL: URL) {
        print("🎬 VideoPlayer: Playing downloaded video")

        // Create player with local file URL
        player = AVPlayer(url: localURL)
        player?.automaticallyWaitsToMinimizeStalling = false
        isLoading = false
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            print("🎬 Audio session setup successfully")
        } catch {
            print("Failed to set audio session category. Error: \(error)")
        }
    }

    private func cleanupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("🎬 Audio session cleanup successfully")
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
