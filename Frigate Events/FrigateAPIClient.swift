
import Foundation

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
    public var baseURL: String
    private var cachedVersion: String?

    init(baseURL: String) {
        self.baseURL = baseURL
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

    func fetchEvents(camera: String? = nil, label: String? = nil, zone: String? = nil, limit: Int? = nil, inProgress: Bool = false, sortBy: String? = nil) async throws -> [FrigateEvent] {
        var components = URLComponents(string: "\(baseURL)/api/events")!
        var queryItems: [URLQueryItem] = []

        if let camera = camera, camera != "all" {
            queryItems.append(URLQueryItem(name: "cameras", value: camera))
        } else {
            queryItems.append(URLQueryItem(name: "cameras", value: "all"))
        }

        if let label = label, label != "all" {
            queryItems.append(URLQueryItem(name: "labels", value: label))
        } else {
            queryItems.append(URLQueryItem(name: "labels", value: "all"))
        }

        if let zone = zone, zone != "all" {
            queryItems.append(URLQueryItem(name: "zones", value: zone))
        } else {
            queryItems.append(URLQueryItem(name: "zones", value: "all"))
        }

        queryItems.append(URLQueryItem(name: "sub_labels", value: "all"))
        queryItems.append(URLQueryItem(name: "time_range", value: "00:00,24:00"))
        queryItems.append(URLQueryItem(name: "timezone", value: "America/New_York"))
        queryItems.append(URLQueryItem(name: "favorites", value: "0"))
        queryItems.append(URLQueryItem(name: "is_submitted", value: "-1"))
        queryItems.append(URLQueryItem(name: "include_thumbnails", value: "0"))

        if inProgress {
            queryItems.append(URLQueryItem(name: "in_progress", value: "1"))
        } else {
            queryItems.append(URLQueryItem(name: "in_progress", value: "0"))
        }

        if let limit = limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        } else {
            queryItems.append(URLQueryItem(name: "limit", value: "50")) // Default limit
        }

        if let sortBy = sortBy {
            queryItems.append(URLQueryItem(name: "order_by", value: sortBy))
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            throw FrigateAPIError.invalidURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw FrigateAPIError.invalidResponse
            }

            // Debug: Log the response for troubleshooting
            if let responseString = String(data: data, encoding: .utf8) {
                print("API Response (first 500 chars): \(String(responseString.prefix(500)))")
            }

            // Get Frigate version to determine parsing strategy
            let version = try await getVersion()
            let versionComponents = parseVersion(version)
            
            // Parse events based on version
            let events = try await parseEventsFromData(data, version: versionComponents)
            return events
            
        } catch let decodingError as DecodingError {
            // If version-based parsing fails, try fallback parsing
            print("Version-based parsing failed, trying fallback: \(decodingError)")
            // We need to get the data again for fallback parsing
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw FrigateAPIError.invalidResponse
            }
            return try await parseEventsWithFallback(data)
        } catch {
            throw FrigateAPIError.networkError(error)
        }
    }
    
    private func parseEventsFromData(_ data: Data, version: (major: Int, minor: Int, patch: Int)) async throws -> [FrigateEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970 // Frigate uses Unix timestamps
        
        // Handle different API formats based on version
        if version.major == 0 && version.minor >= 16 {
            // Frigate v0.16.x+ format - latest changes
            return try parseV16Events(data: data, decoder: decoder)
        } else if version.major == 0 && version.minor >= 15 {
            // Frigate v0.15.x format
            return try parseV15Events(data: data, decoder: decoder)
        } else if version.major == 0 && version.minor >= 13 {
            // Frigate v0.13.x format
            return try parseV13Events(data: data, decoder: decoder)
        } else if version.major == 0 && version.minor >= 12 {
            // Frigate v0.12.x format
            return try parseV12Events(data: data, decoder: decoder)
        } else {
            // Try legacy format as fallback
            return try parseLegacyEvents(data: data, decoder: decoder)
        }
    }
    
    private func parseV16Events(data: Data, decoder: JSONDecoder) throws -> [FrigateEvent] {
        // v0.16.x+ format - handle latest API changes
        do {
            // First try standard array format
            let events = try decoder.decode([FrigateEvent].self, from: data)
            print("Successfully parsed v0.16+ events using standard format")
            return events
        } catch {
            print("Standard v0.16+ parsing failed, trying alternative formats: \(error)")
            
            // Try wrapped format with pagination
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let eventsArray = json["events"] as? [[String: Any]] {
                    print("Found events in 'events' wrapper")
                    return try eventsArray.compactMap { eventDict in
                        try parseEventFromDict(eventDict)
                    }
                }
                
                // Try alternative v0.16 format with different wrapper
                if let eventsArray = json["data"] as? [[String: Any]] {
                    print("Found events in 'data' wrapper")
                    return try eventsArray.compactMap { eventDict in
                        try parseEventFromDict(eventDict)
                    }
                }
                
                // Try with results wrapper
                if let results = json["results"] as? [[String: Any]] {
                    print("Found events in 'results' wrapper")
                    return try results.compactMap { eventDict in
                        try parseEventFromDict(eventDict)
                    }
                }
                
                // Log the JSON structure for debugging
                print("v0.16+ JSON structure: \(json.keys)")
            }
            
            // If all else fails, try legacy parsing
            print("Falling back to legacy parsing for v0.16+")
            return try parseLegacyEvents(data: data, decoder: decoder)
        }
    }
    
    private func parseV15Events(data: Data, decoder: JSONDecoder) throws -> [FrigateEvent] {
        // v0.15.x+ format - events might be wrapped differently
        do {
            let events = try decoder.decode([FrigateEvent].self, from: data)
            return events
        } catch {
            // Try alternative v0.15 format if direct array fails
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let eventsArray = json["events"] as? [[String: Any]] {
                return try eventsArray.compactMap { eventDict in
                    try parseEventFromDict(eventDict)
                }
            }
            throw error
        }
    }
    
    private func parseV13Events(data: Data, decoder: JSONDecoder) throws -> [FrigateEvent] {
        // v0.13.x format - standard array format
        return try decoder.decode([FrigateEvent].self, from: data)
    }
    
    private func parseV12Events(data: Data, decoder: JSONDecoder) throws -> [FrigateEvent] {
        // v0.12.x format - might have different field names
        do {
            return try decoder.decode([FrigateEvent].self, from: data)
        } catch {
            // Try with legacy field mappings
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return try json.compactMap { eventDict in
                    try parseLegacyEventFromDict(eventDict)
                }
            }
            throw error
        }
    }
    
    private func parseLegacyEvents(data: Data, decoder: JSONDecoder) throws -> [FrigateEvent] {
        // Fallback for older versions
        if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return try json.compactMap { eventDict in
                try parseLegacyEventFromDict(eventDict)
            }
        }
        return try decoder.decode([FrigateEvent].self, from: data)
    }
    
    private func parseEventFromDict(_ dict: [String: Any]) throws -> FrigateEvent {
        // Parse modern event format
        guard let id = dict["id"] as? String,
              let camera = dict["camera"] as? String,
              let label = dict["label"] as? String,
              let startTime = dict["start_time"] as? Double,
              let hasClip = dict["has_clip"] as? Bool,
              let hasSnapshot = dict["has_snapshot"] as? Bool,
              let zones = dict["zones"] as? [String],
              let retainIndefinitely = dict["retain_indefinitely"] as? Bool else {
            throw FrigateAPIError.decodingError(DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Missing required fields")))
        }
        
        let endTime = dict["end_time"] as? Double
        let data = parseEventData(dict["data"] as? [String: Any])
        let box = dict["box"] as? [Double]
        let falsePositive = dict["false_positive"] as? Bool
        let plusId = dict["plus_id"] as? String
        let subLabel = dict["sub_label"] as? String
        let topScore = dict["top_score"] as? Double
        
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
    
    private func parseLegacyEventFromDict(_ dict: [String: Any]) throws -> FrigateEvent {
        // Parse legacy event format with different field names
        guard let id = dict["id"] as? String,
              let camera = dict["camera"] as? String,
              let label = dict["label"] as? String,
              let startTime = dict["start_time"] as? Double,
              let hasClip = dict["has_clip"] as? Bool,
              let hasSnapshot = dict["has_snapshot"] as? Bool,
              let zones = dict["zones"] as? [String],
              let retainIndefinitely = dict["retain_indefinitely"] as? Bool else {
            throw FrigateAPIError.decodingError(DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Missing required fields in legacy format")))
        }
        
        let endTime = dict["end_time"] as? Double
        let data = parseEventData(dict["data"] as? [String: Any])
        let box = dict["box"] as? [Double]
        let falsePositive = dict["false_positive"] as? Bool
        let plusId = dict["plus_id"] as? String
        let subLabel = dict["sub_label"] as? String
        let topScore = dict["top_score"] as? Double
        
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
              let attributes = dict["attributes"] as? [String],
              let box = dict["box"] as? [Double],
              let region = dict["region"] as? [Double],
              let score = dict["score"] as? Double,
              let topScore = dict["top_score"] as? Double,
              let type = dict["type"] as? String else {
            return nil
        }
        
        return EventData(
            attributes: attributes,
            box: box,
            region: region,
            score: score,
            top_score: topScore,
            type: type
        )
    }
    
    private func parseEventsWithFallback(_ data: Data) async throws -> [FrigateEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        // Try multiple parsing strategies in order of likelihood
        
        // Strategy 1: Direct array parsing (most common)
        do {
            let events = try decoder.decode([FrigateEvent].self, from: data)
            print("Fallback: Successfully parsed events as direct array")
            return events
        } catch {
            print("Fallback: Direct array parsing failed: \(error)")
        }
        
        // Strategy 2: Try JSON parsing with different wrappers
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Try "events" wrapper
                if let eventsArray = json["events"] as? [[String: Any]] {
                    print("Fallback: Found events in 'events' wrapper")
                    return try eventsArray.compactMap { eventDict in
                        try parseEventFromDict(eventDict)
                    }
                }
                
                // Try "data" wrapper
                if let eventsArray = json["data"] as? [[String: Any]] {
                    print("Fallback: Found events in 'data' wrapper")
                    return try eventsArray.compactMap { eventDict in
                        try parseEventFromDict(eventDict)
                    }
                }
                
                // Try "results" wrapper
                if let results = json["results"] as? [[String: Any]] {
                    print("Fallback: Found events in 'results' wrapper")
                    return try results.compactMap { eventDict in
                        try parseEventFromDict(eventDict)
                    }
                }
                
                // Note: json is already a [String: Any], so we can't cast it to [[String: Any]]
                // This was an incorrect cast that would always fail
                
                print("Fallback: JSON structure keys: \(json.keys)")
            }
        } catch {
            print("Fallback: JSON parsing failed: \(error)")
        }
        
        // Strategy 3: Try legacy parsing - try parsing as direct array first
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                print("Fallback: Trying legacy parsing as direct array")
                return try json.compactMap { eventDict in
                    try parseLegacyEventFromDict(eventDict)
                }
            }
        } catch {
            print("Fallback: Legacy parsing failed: \(error)")
        }
        
        // If all strategies fail, throw a descriptive error
        throw FrigateAPIError.decodingError(DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Could not parse events data with any known format. Data length: \(data.count) bytes"
            )
        ))
    }

    func fetchCameras() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/config") else {
            throw FrigateAPIError.invalidURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
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
    
    func fetchVersion() async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/version") else {
            throw FrigateAPIError.invalidURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw FrigateAPIError.invalidResponse
            }
            
            // Debug: Log the version response
            if let responseString = String(data: data, encoding: .utf8) {
                print("Version API Response: \(responseString)")
            }
            
            // Try multiple parsing strategies for version info
            let version = try parseVersionFromData(data)
            return version
            
        } catch {
            throw FrigateAPIError.networkError(error)
        }
    }
    
    private func parseVersionFromData(_ data: Data) throws -> String {
        // Strategy 1: Try standard JSON format with "version" field
        do {
            let versionInfo = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            if let version = versionInfo?["version"] as? String {
                print("Found version in 'version' field: \(version)")
                return version
            }
        } catch {
            print("Strategy 1 failed: \(error)")
        }
        
        // Strategy 2: Try different field names
        do {
            let versionInfo = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            if let version = versionInfo?["frigate_version"] as? String {
                print("Found version in 'frigate_version' field: \(version)")
                return version
            }
            if let version = versionInfo?["server_version"] as? String {
                print("Found version in 'server_version' field: \(version)")
                return version
            }
            if let version = versionInfo?["api_version"] as? String {
                print("Found version in 'api_version' field: \(version)")
                return version
            }
        } catch {
            print("Strategy 2 failed: \(error)")
        }
        
        // Strategy 3: Try parsing as direct string
        do {
            if let versionString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                // Check if it looks like a version string using older string methods
                let versionPattern = #"^\d+\.\d+\.\d+"#
                if versionString.range(of: versionPattern, options: .regularExpression) != nil {
                    print("Found version as direct string: \(versionString)")
                    return versionString
                }
            }
        } catch {
            print("Strategy 3 failed: \(error)")
        }
        
        // Strategy 4: Try to extract version from any JSON structure
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let jsonString = String(describing: json)
            
            // Look for version pattern in the JSON string using older string methods
            let versionPattern = #""version"\s*:\s*"([^"]+)""#
            if let range = jsonString.range(of: versionPattern, options: .regularExpression),
               let matchRange = jsonString.range(of: #"([^"]+)"#, options: .regularExpression, range: range) {
                let version = String(jsonString[matchRange])
                print("Extracted version from JSON string: \(version)")
                return version
            }
        } catch {
            print("Strategy 4 failed: \(error)")
        }
        
        throw FrigateAPIError.invalidResponse
    }
}
