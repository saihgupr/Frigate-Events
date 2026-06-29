//
//  Models.swift
//  FrigateEventsiOS
//
//  Created by Chris LaPointe on 2024
//

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

    func hlsUrl(baseURL: String) -> URL? {
        URL(string: "\(baseURL)/vod/event/\(id)/master.m3u8")
    }

    func clipUrl(baseURL: String) -> URL? {
        URL(string: "\(baseURL)/api/events/\(id)/clip.mp4")
    }
    
    // Alternative clip URL methods for Frigate 15 compatibility
    func clipUrlAlternative1(baseURL: String) -> URL? {
        // Try without .mp4 extension
        URL(string: "\(baseURL)/api/events/\(id)/clip")
    }
    
    func clipUrlAlternative2(baseURL: String) -> URL? {
        // Try with different path structure
        URL(string: "\(baseURL)/api/events/\(id)/recording")
    }
    
    func clipUrlAlternative3(baseURL: String) -> URL? {
        // Try with .mov extension
        URL(string: "\(baseURL)/api/events/\(id)/clip.mov")
    }

    func clipUrlAlternative4(baseURL: String) -> URL? {
        // Try with .mkv extension (common in Frigate)
        URL(string: "\(baseURL)/api/events/\(id)/clip.mkv")
    }

    func clipUrlAlternative5(baseURL: String) -> URL? {
        // Try with .avi extension
        URL(string: "\(baseURL)/api/events/\(id)/clip.avi")
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

    // Explicit memberwise initializer since we added a custom Decodable init
    init(id: String, camera: String, label: String, start_time: Double, end_time: Double?, has_clip: Bool, has_snapshot: Bool, zones: [String], data: EventData?, box: [Double]?, false_positive: Bool?, plus_id: String?, retain_indefinitely: Bool, sub_label: String?, top_score: Double?) {
        self.id = id
        self.camera = camera
        self.label = label
        self.start_time = start_time
        self.end_time = end_time
        self.has_clip = has_clip
        self.has_snapshot = has_snapshot
        self.zones = zones
        self.data = data
        self.box = box
        self.false_positive = false_positive
        self.plus_id = plus_id
        self.retain_indefinitely = retain_indefinitely
        self.sub_label = sub_label
        self.top_score = top_score
    }

    // MARK: - Custom Decodable
    enum CodingKeys: String, CodingKey {
        case id, camera, label
        case start_time = "startTime"
        case end_time = "endTime"
        case has_clip = "hasClip"
        case has_snapshot = "hasSnapshot"
        case zones, data, box
        case false_positive = "falsePositive"
        case plus_id = "plusId"
        case retain_indefinitely = "retainIndefinitely"
        case sub_label = "subLabel"
        case top_score = "topScore"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        camera = try container.decode(String.self, forKey: .camera)
        label = try container.decode(String.self, forKey: .label)
        start_time = try container.decode(Double.self, forKey: .start_time)
        end_time = try container.decodeIfPresent(Double.self, forKey: .end_time)
        has_clip = try container.decodeIfPresent(Bool.self, forKey: .has_clip) ?? true
        has_snapshot = try container.decodeIfPresent(Bool.self, forKey: .has_snapshot) ?? true
        zones = try container.decodeIfPresent([String].self, forKey: .zones) ?? []
        data = try container.decodeIfPresent(EventData.self, forKey: .data)
        box = try container.decodeIfPresent([Double].self, forKey: .box)
        false_positive = try container.decodeIfPresent(Bool.self, forKey: .false_positive)
        plus_id = try container.decodeIfPresent(String.self, forKey: .plus_id)
        retain_indefinitely = try container.decodeIfPresent(Bool.self, forKey: .retain_indefinitely) ?? false
        sub_label = try container.decodeIfPresent(String.self, forKey: .sub_label)
        top_score = try container.decodeIfPresent(Double.self, forKey: .top_score)
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
