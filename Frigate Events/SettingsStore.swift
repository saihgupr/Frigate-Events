
import Foundation
import Combine

class SettingsStore: ObservableObject {
    @Published var frigateBaseURL: String {
        didSet {
            UserDefaults.standard.set(frigateBaseURL, forKey: "frigateBaseURL")
        }
    }
    
    @Published var frigateVersion: String = "Unknown"

    @Published var availableLabels: [String] = []
    @Published var selectedLabels: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedLabels), forKey: "selectedLabels")
        }
    }

    @Published var availableZones: [String] = []
    @Published var selectedZones: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedZones), forKey: "selectedZones")
        }
    }

    @Published var availableCameras: [String] = []
    @Published var selectedCameras: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedCameras), forKey: "selectedCameras")
        }
    }

    init() {
        self.frigateBaseURL = UserDefaults.standard.string(forKey: "frigateBaseURL") ?? "http://192.168.1.168:5000"
        
        if let savedLabels = UserDefaults.standard.array(forKey: "selectedLabels") as? [String] {
            self.selectedLabels = Set(savedLabels)
        } else {
            self.selectedLabels = []
        }

        if let savedZones = UserDefaults.standard.array(forKey: "selectedZones") as? [String] {
            self.selectedZones = Set(savedZones)
        } else {
            self.selectedZones = []
        }

        if let savedCameras = UserDefaults.standard.array(forKey: "selectedCameras") as? [String] {
            self.selectedCameras = Set(savedCameras)
        } else {
            self.selectedCameras = []
        }
    }
    
    @MainActor
    func fetchFrigateVersion(apiClient: FrigateAPIClient) async {
        do {
            let version = try await apiClient.fetchVersion()
            self.frigateVersion = version
        } catch let apiError as FrigateAPIError {
            switch apiError {
            case .invalidURL:
                self.frigateVersion = "Error: Invalid URL"
            case .networkError(let error):
                self.frigateVersion = "Error: Network issue - \(error.localizedDescription)"
            case .invalidResponse:
                self.frigateVersion = "Error: Invalid response format"
            case .unsupportedVersion(let version):
                self.frigateVersion = "Error: Unsupported version \(version)"
            default:
                self.frigateVersion = "Error: \(apiError.localizedDescription)"
            }
        } catch {
            self.frigateVersion = "Error: \(error.localizedDescription)"
        }
    }
}
