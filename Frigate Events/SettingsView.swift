import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.presentationMode) var presentationMode

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
    }
    
    private func isVersionSupported(_ versionString: String) -> Bool {
        let components = versionString.components(separatedBy: ".")
        guard let major = Int(components.first ?? "0"),
              let minor = Int(components.count > 1 ? components[1] : "0") else {
            return false
        }
        
        // Support Frigate v0.12.x and later
        if major == 0 && minor >= 12 {
            return true
        }
        
        // Support Frigate v1.0.0 and later
        if major >= 1 {
            return true
        }
        
        return false
    }
    
    private func getCompatibilityStatus(_ versionString: String) -> (status: String, color: Color) {
        let components = versionString.components(separatedBy: ".")
        guard let major = Int(components.first ?? "0"),
              let minor = Int(components.count > 1 ? components[1] : "0") else {
            return ("Unknown", .gray)
        }
        
        // Fully supported versions
        if (major == 0 && minor >= 13) || major >= 1 {
            return ("Fully Supported", .green)
        }
        
        // Limited support for older versions
        if major == 0 && minor >= 12 {
            return ("Limited Support", .orange)
        }
        
        // Unsupported versions
        return ("Unsupported", .red)
    }

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Frigate")) {
                        TextField("Base URL", text: $settingsStore.frigateBaseURL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    Section(header: Text("Label Filter")) {
                        if settingsStore.availableLabels.isEmpty {
                            Text("No labels found in recent events.")
                                .foregroundColor(.gray)
                        } else {
                            List(settingsStore.availableLabels, id: \.self) { label in
                                Button(action: {
                                    if settingsStore.selectedLabels.contains(label) {
                                        settingsStore.selectedLabels.remove(label)
                                    } else {
                                        settingsStore.selectedLabels.insert(label)
                                    }
                                }) {
                                    HStack {
                                        Text(label.toFriendlyName())
                                            .foregroundColor(.primary)
                                        if settingsStore.selectedLabels.contains(label) {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Section(header: Text("Zone Filter")) {
                        if settingsStore.availableZones.isEmpty {
                            Text("No zones found in recent events.")
                                .foregroundColor(.gray)
                        } else {
                            List(settingsStore.availableZones, id: \.self) { zone in
                                Button(action: {
                                    if settingsStore.selectedZones.contains(zone) {
                                        settingsStore.selectedZones.remove(zone)
                                    } else {
                                        settingsStore.selectedZones.insert(zone)
                                    }
                                }) {
                                    HStack {
                                        Text(zone.toFriendlyName())
                                            .foregroundColor(.primary)
                                        if settingsStore.selectedZones.contains(zone) {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } // End of Zone Filter Section

                    Section(header: Text("Camera Filter")) {
                        if settingsStore.availableCameras.isEmpty {
                            Text("No cameras found. Pull to refresh on the main screen to populate this list.")
                                .foregroundColor(.gray)
                        } else {
                            List(settingsStore.availableCameras, id: \.self) { camera in
                                Button(action: {
                                    if settingsStore.selectedCameras.contains(camera) {
                                        settingsStore.selectedCameras.remove(camera)
                                    } else {
                                        settingsStore.selectedCameras.insert(camera)
                                    }
                                }) {
                                    HStack {
                                        Text(camera.toFriendlyName())
                                            .foregroundColor(.primary)
                                        if settingsStore.selectedCameras.contains(camera) {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } // End of Camera Filter Section

                    Section {
                        HStack {
                            Spacer()
                            Text("v\(appVersion)")
                                .font(.footnote)
                                .foregroundColor(Color.gray.opacity(0.6))
                                .padding(.top, -20)
                            Spacer()
                        }
                        .listRowBackground(Color(.systemGroupedBackground))
                        .listRowInsets(EdgeInsets())
                    }
                }
                .padding(.bottom, -60)

                
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let settingsStore = SettingsStore()
        settingsStore.availableLabels = ["person", "car", "dog"]
        settingsStore.selectedLabels = ["person"]
        settingsStore.availableZones = ["porch", "driveway"]
        settingsStore.selectedZones = ["porch"]
        settingsStore.availableCameras = ["front_door", "driveway_camera", "wyze_camera"]
        settingsStore.selectedCameras = ["front_door"]

        return SettingsView()
            .environmentObject(settingsStore)
    }
}
