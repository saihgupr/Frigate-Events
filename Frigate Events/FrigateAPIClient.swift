//
//  FrigateAPIClient.swift
//  FrigateEventsiOS
//
//  Created by Chris LaPointe on 2024
//

import Foundation
import SwiftUI

enum FrigateAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case invalidResponse
    case unsupportedVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL for the Frigate API is invalid."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode Frigate events: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from the Frigate API."
        case .unsupportedVersion(let version):
            return "Unsupported Frigate version: \(version). Please upgrade to a supported version."
        }
    }
}

class FrigateAPIClient: ObservableObject {
    private let session: URLSession
    private let decoder: JSONDecoder
    var baseURL: String
    private var cachedVersion: String?

    init(baseURL: String = "http://192.168.1.204:5000") {
        self.baseURL = baseURL
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .secondsSince1970 // Frigate uses Unix timestamps
    }

    private func getVersion() async throws -> String {
        if let cached = cachedVersion {
            return cached
        }
        do {
            let version = try await fetchVersion()
            cachedVersion = version
            return version
        } catch {
            // If version detection fails, use a default version and log the error
            print("Warning: Could not detect Frigate version, using default: \(error.localizedDescription)")
            cachedVersion = "0.13.0" // Default to a known working version
            return "0.13.0"
        }
    }

    private func parseVersion(_ versionString: String) -> (major: Int, minor: Int, patch: Int) {
        let components = versionString.components(separatedBy: ".")
        let major = Int(components.first ?? "0") ?? 0
        let minor = Int(components.count > 1 ? components[1] : "0") ?? 0
        let patch = Int(components.count > 2 ? components[2] : "0") ?? 0
        return (major, minor, patch)
    }

    // MARK: - Event Fetching

    func fetchEvents(
        camera: String? = nil,
        label: String? = nil,
        zone: String? = nil,
        limit: Int? = nil,
        inProgress: Bool = false,
        sortBy: String? = nil
    ) async throws -> [FrigateEvent] {
        var components = URLComponents(string: "\(baseURL)/api/events")!
        var queryItems: [URLQueryItem] = []

        if let camera = camera {
            queryItems.append(URLQueryItem(name: "cameras", value: camera))
        } else {
            queryItems.append(URLQueryItem(name: "cameras", value: "all"))
        }

        if let label = label {
            queryItems.append(URLQueryItem(name: "labels", value: label))
        } else {
            queryItems.append(URLQueryItem(name: "labels", value: "all"))
        }

        if let zone = zone {
            queryItems.append(URLQueryItem(name: "zones", value: zone))
        } else {
            queryItems.append(URLQueryItem(name: "zones", value: "all"))
        }

        queryItems.append(contentsOf: [
            URLQueryItem(name: "sub_labels", value: "all"),
            URLQueryItem(name: "time_range", value: "00:00,24:00"),
            URLQueryItem(name: "timezone", value: "America/New_York"),
            URLQueryItem(name: "favorites", value: "0"),
            URLQueryItem(name: "is_submitted", value: "-1"),
            URLQueryItem(name: "include_thumbnails", value: "0"),
            URLQueryItem(name: "in_progress", value: inProgress ? "1" : "0")
        ])

        if let limit = limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }

        if let sortBy = sortBy {
            queryItems.append(URLQueryItem(name: "order_by", value: sortBy))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw FrigateAPIError.invalidURL
        }

        print("🌐 API Call: \(url)")
        
        do {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
                throw FrigateAPIError.invalidResponse
        }
        
        print("📡 HTTP Response: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("❌ HTTP Error: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Response body: \(responseString)")
            }
                throw FrigateAPIError.invalidResponse
        }

        print("📊 Response data size: \(data.count) bytes")
        
            // Debug: Log the response for troubleshooting
            if let responseString = String(data: data, encoding: .utf8) {
                print("API Response (first 500 chars): \(String(responseString.prefix(500)))")
            }

            let version = try await getVersion()
            let versionComponents = parseVersion(version)

            do {
                return try await parseEventsFromData(data, version: versionComponents)
            } catch let decodingError {
                print("Version-based parsing failed, trying fallback: \(decodingError)")
                return try await parseEventsWithFallback(data)
            }
        } catch {
            throw FrigateAPIError.networkError(error)
        }
    }

    private func parseEventsFromData(_ data: Data, version: (major: Int, minor: Int, patch: Int)) async throws -> [FrigateEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970 // Frigate uses Unix timestamps
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Frigate API has inconsistent response formats. We try a few common structures.
        // 1. Direct array of events: [ {event1}, {event2} ]
        if let events = try? decoder.decode([FrigateEvent].self, from: data) {
            print("Successfully parsed events as a direct array.")
            return events
        }

        // 2. Wrapped in a dictionary: { "events": [ ... ], "other_key": ... }
        // We check for common wrapper keys like "events", "data", "results".
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let wrapperKeys = ["events", "data", "results"]
            for key in wrapperKeys {
                if let eventsArray = json[key] as? [[String: Any]] {
                    print("Found events in '\(key)' wrapper.")
                    // Re-serialize the inner array to decode it with the JSONDecoder
                    let eventsData = try JSONSerialization.data(withJSONObject: eventsArray)
                    if let events = try? decoder.decode([FrigateEvent].self, from: eventsData) {
                        return events
                    }
                }
            }
        }

        // 3. Fallback to manual dictionary parsing if automatic decoding fails.
        // This is useful for older/legacy formats with slightly different field names.
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            print("Attempting to parse events manually from a JSON array.")
            return try jsonArray.compactMap { try parseEventFromDict($0) }
        }

        // If all parsing strategies fail, throw an error.
        throw FrigateAPIError.decodingError(DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Could not parse events data with any known format.")
        ))
    }

    private func parseEventsWithFallback(_ data: Data) async throws -> [FrigateEvent] {
        print("Executing fallback parsing.")
        // The new parseEventsFromData is generic enough to serve as the fallback.
        return try await parseEventsFromData(data, version: (0, 0, 0)) // Pass a dummy version
    }

    private func parseEventFromDict(_ dict: [String: Any]) throws -> FrigateEvent {
        // This function handles both modern and legacy formats by checking for required fields.
        guard let id = dict["id"] as? String,
              let camera = dict["camera"] as? String,
              let label = dict["label"] as? String,
              let startTime = dict["start_time"] as? Double else {
            throw FrigateAPIError.decodingError(DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Missing required fields (id, camera, label, start_time)")))
        }

        let hasClip = dict["has_clip"] as? Bool ?? true
        let hasSnapshot = dict["has_snapshot"] as? Bool ?? true

        // Optional fields
        let endTime = dict["end_time"] as? Double
        let zones = dict["zones"] as? [String] ?? []
        let retainIndefinitely = dict["retain_indefinitely"] as? Bool ?? false
        let data = parseEventData(dict["data"] as? [String: Any])
        let box = dict["box"] as? [Double]
        let falsePositive = dict["false_positive"] as? Bool
        let plusId = dict["plus_id"] as? String
        let subLabel = dict["sub_label"] as? String
        let topScore = dict["top_score"] as? Double
        _ = dict["thumbnail"] as? String

        return FrigateEvent(
            id: id,
            camera: camera,
            label: label,
            start_time: startTime,
            end_time: endTime,
            has_clip: hasClip,
            has_snapshot: hasSnapshot,
            zones: zones,
            data: data,
            box: box,
            false_positive: falsePositive,
            plus_id: plusId,
            retain_indefinitely: retainIndefinitely,
            sub_label: subLabel,
            top_score: topScore
        )
    }

    private func parseEventData(_ dataDict: [String: Any]?) -> EventData? {
        guard let dict = dataDict,
              let score = dict["score"] as? Double,
              let topScore = dict["top_score"] as? Double,
              let type = dict["type"] as? String else {
            return nil
        }

        // Optional fields in EventData
        let attributes = dict["attributes"] as? [String] ?? []
        let box = dict["box"] as? [Double] ?? []
        let region = dict["region"] as? [Double] ?? []
        _ = dict["average_estimated_speed"] as? Double
        _ = dict["velocity_angle"] as? Double
        _ = dict["max_severity"] as? String
        _ = dict["path_data"] as? [[Double]]

        return EventData(
            attributes: attributes,
            box: box,
            region: region,
            score: score,
            top_score: topScore,
            type: type
        )
    }

    // MARK: - Version Fetching

    func fetchVersion() async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/version") else {
            throw FrigateAPIError.invalidURL
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw FrigateAPIError.invalidResponse
            }

            if let responseString = String(data: data, encoding: .utf8) {
                print("Version API Response: \(responseString)")
            }

            return try parseVersionFromData(data)

        } catch {
            throw FrigateAPIError.networkError(error)
        }
    }

    private func parseVersionFromData(_ data: Data) throws -> String {
        // Strategy 1: Try to parse as JSON and look for a "version" key.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let versionKeys = ["version", "frigate_version", "server_version", "api_version"]
            for key in versionKeys {
                if let version = json[key] as? String {
                    print("Found version '\(version)' with key '\(key)'.")
            return version
                }
            }
        }

        // Strategy 2: Try to parse as a plain string.
        if let versionString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            // Use a simple regex to validate that the string looks like a version number.
            let versionPattern = #"^\d+\.\d+(\.\d+.*)?"#
            if versionString.range(of: versionPattern, options: .regularExpression) != nil {
                print("Parsed version as a plain string: \(versionString)")
            return versionString
            }
        }

        // Strategy 3: Extract from a larger JSON string if the root is not a dictionary.
        if let jsonString = String(data: data, encoding: .utf8) {
            let versionPattern = #"version"\s*:\s*"([^"]+)""#
            if let range = jsonString.range(of: versionPattern, options: .regularExpression) {
                let capturedGroup = jsonString[range]
                let version = String(capturedGroup.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "") ?? "")
                if !version.isEmpty {
                    print("Extracted version from JSON string: \(version)")
                    return version
                }
            }
        }

        throw FrigateAPIError.decodingError(
            DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Could not determine Frigate version from API response.")
            )
        )
    }

    // MARK: - Available Items Fetching

    func fetchAvailableLabels(limit: Int = 100) async throws -> [String] {
        let events = try await fetchEvents(limit: limit)
        return events.compactMap { $0.label }.removingDuplicates().sorted()
    }

    func fetchAvailableZones(limit: Int = 100) async throws -> [String] {
        let events = try await fetchEvents(limit: limit)
        return events.flatMap { $0.zones }.removingDuplicates().sorted()
    }

    func fetchAvailableCameras(limit: Int = 100) async throws -> [String] {
        let events = try await fetchEvents(limit: limit)
        return events.map { $0.camera }.removingDuplicates().sorted()
    }

    // MARK: - Authentication (Frigate 0.17+)
    
    func login(username: String, password: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/login") else {
            throw FrigateAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let loginData = ["user": username, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: loginData)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FrigateAPIError.invalidResponse
            }
            
            print("📡 Login Response: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ Login failed: \(responseString)")
                }
                throw FrigateAPIError.invalidResponse
            }
            
            // Parse the token from the response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String ?? json["token"] as? String {
                print("✅ Login successful, token received")
                return token
            }
            
            // If the response is just the token as a string
            if let tokenString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                print("✅ Login successful, token received (plain text)")
                return tokenString
            }
            
            throw FrigateAPIError.decodingError(
                DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Could not parse authentication token from response.")
                )
            )
        } catch {
            throw FrigateAPIError.networkError(error)
        }
    }
    
    // MARK: - Connectivity Test
    
    func testConnectivity() async throws -> Bool {
        let url = URL(string: "\(baseURL)/api/version")!
        print("🔌 Testing connectivity to: \(url)")
        
        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Connectivity test successful: HTTP \(httpResponse.statusCode)")
                return true
            }
        } catch {
            print("❌ Connectivity test failed: \(error.localizedDescription)")
        }
        return false
    }

    // MARK: - Video URL Testing and Debugging

    func testVideoURL(_ url: URL) async -> (success: Bool, statusCode: Int?, contentType: String?, error: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, nil, nil, "Invalid response")
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
            return (true, httpResponse.statusCode, contentType, nil)
        } catch {
            return (false, nil, nil, error.localizedDescription)
        }
    }

    func debugVideoAccess(eventId: String) async {
        let baseURL = self.baseURL
        let urls = [
            "\(baseURL)/api/events/\(eventId)/clip.mp4",
            "\(baseURL)/api/events/\(eventId)/clip",
            "\(baseURL)/api/events/\(eventId)/recording",
            "\(baseURL)/api/events/\(eventId)/clip.mov"
        ]

        print("=== Video URL Debug for Event \(eventId) ===")
        for (index, urlString) in urls.enumerated() {
            guard let url = URL(string: urlString) else {
                print("Format \(index + 1): Invalid URL")
                continue
            }

            let result = await testVideoURL(url)
            print("Format \(index + 1): \(urlString)")
            print("  Success: \(result.success)")
            print("  Status: \(result.statusCode ?? -1)")
            print("  Content-Type: \(result.contentType ?? "Unknown")")
            if let error = result.error {
                print("  Error: \(error)")
            }
            print("---")
        }
    }

    func testSpecificVideoURL(eventId: String) async {
        let baseURL = self.baseURL
        let testURL = "\(baseURL)/api/events/\(eventId)/clip.mp4"

        print("🔍 Testing specific video URL: \(testURL)")

        guard let url = URL(string: testURL) else {
            print("❌ Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response")
                return
            }

            print("📊 Status Code: \(httpResponse.statusCode)")
            print("📊 Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "Unknown")")
            print("📊 Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "Unknown")")
            print("📊 All Headers: \(httpResponse.allHeaderFields)")

        } catch {
            print("❌ Error testing URL: \(error.localizedDescription)")
        }
    }

    func testServerConnectivity() async {
        let baseURL = self.baseURL
        let testURL = "\(baseURL)/api/version"

        print("🔍 Testing server connectivity: \(testURL)")

        guard let url = URL(string: testURL) else {
            print("❌ Invalid URL")
            return
        }

        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response")
                return
            }

            print("📊 Server Status Code: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📊 Server Response: \(responseString)")
            }

        } catch {
            print("❌ Error testing server: \(error.localizedDescription)")
        }
    }

    // MARK: - Camera Configuration (Alternative method)

    func fetchCameras() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/config") else {
            throw FrigateAPIError.invalidURL
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw FrigateAPIError.invalidResponse
            }
            let config = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            let cameras = config?["cameras"] as? [String: Any]
            return cameras?.keys.map { $0 }.sorted() ?? []
        } catch {
            throw FrigateAPIError.networkError(error)
        }
    }
}

// MARK: - Array Extensions

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
