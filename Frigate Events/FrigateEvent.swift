
import Foundation

extension String {
    func toFriendlyName() -> String {
        self.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - FrigateEvent
struct FrigateEvent: Codable, Identifiable {
    let id: String
    let camera: String
    let label: String
    let start_time: Double
    let end_time: Double?
    let has_clip: Bool
    let has_snapshot: Bool
    let zones: [String]
    let data: EventData?
    let box: [Double]? // This can be null in the JSON, so it's optional
    let false_positive: Bool? // This can be null in the JSON, so it's optional
    let plus_id: String? // This can be null in the JSON, so it's optional
    let retain_indefinitely: Bool
    let sub_label: String? // This can be null in the JSON, so it's optional
    let top_score: Double? // This can be null in the JSON, so it's optional

    var duration: TimeInterval? {
        guard let end = end_time else {
            return nil
        }
        return end - start_time
    }

    func thumbnailUrl(baseURL: String) -> URL? {
        URL(string: "\(baseURL)/api/events/\(id)/thumbnail.jpg")
    }

    func clipUrl(baseURL: String) -> URL? {
        URL(string: "\(baseURL)/api/events/\(id)/clip.mp4")
    }

    func fullSizeSnapshotUrl(baseURL: String) -> URL? {
        URL(string: "\(baseURL)/api/events/\(id)/snapshot.jpg")
    }

    var friendlyCameraName: String {
        camera.toFriendlyName()
    }

    var friendlyLabelName: String {
        label.toFriendlyName()
    }

    var friendlyZoneNames: String {
        zones.map { $0.toFriendlyName() }.joined(separator: ", ")
    }
}

// MARK: - EventData
struct EventData: Codable {
    let attributes: [String]
    let box: [Double]
    let region: [Double]
    let score: Double
    let top_score: Double
    let type: String
}
