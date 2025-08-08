
import Foundation

enum FrigateAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case invalidResponse

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
        }
    }
}

class FrigateAPIClient: ObservableObject {
    public var baseURL: String

    init(baseURL: String) {
        self.baseURL = baseURL
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

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970 // Frigate uses Unix timestamps

            let events = try decoder.decode([FrigateEvent].self, from: data)
            return events
        } catch let decodingError as DecodingError {
            throw FrigateAPIError.decodingError(decodingError)
        } catch {
            throw FrigateAPIError.networkError(error)
        }
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
}
