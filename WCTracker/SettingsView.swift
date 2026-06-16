import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    enum ImageTarget { case badge, ball }

    @ObservedObject var store: MatchCenterStore
    @Environment(\.dismiss) private var dismiss
    @State private var badgePick: PhotosPickerItem?
    @State private var imageTarget: ImageTarget = .badge
    @State private var showSourceDialog = false
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var showFileImporter = false

    /// Route a picked image to the badge or the ball, depending on what was tapped.
    private func applyPickedImage(_ data: Data) {
        switch imageTarget {
        case .badge: store.setBadge(data: data)
        case .ball: store.setBall(data: data)
        }
    }

    /// Bridges the ColorPicker's `Color` to the store's persisted hex string.
    private var backgroundColor: Binding<Color> {
        Binding(
            get: { store.backgroundColor },
            set: { store.backgroundColorHex = $0.hexString() }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Demo mode", isOn: $store.demoMode)
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Shows a self-contained sample match (France v Senegal) with full lineups, goals, stats, stadium and weather — and a ball that moves around the pitch — so you can test the layout without a live match or network. You can also launch with the --demo argument.")
                }

                Section {
                    ColorPicker("Background", selection: backgroundColor, supportsOpacity: false)
                    Button("Reset to black") { store.backgroundColorHex = "000000" }
                        .disabled(store.backgroundColorHex.uppercased() == "000000")
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("The full-screen background color behind the scoreboard and pitch.")
                }

                Section {
                    Toggle("Accurate match minute", isOn: $store.useBroadcastClock)
                } header: {
                    Text("Scoreboard Clock")
                } footer: {
                    Text("On: shows the broadcast's minute exactly as the feed reports it (e.g. 37', 45'+2'), guaranteed to match the TV. Off: shows a running MM:SS clock — smoother, but the seconds are estimated since the feed only reports whole minutes.")
                }

                Section {
                    let hasBadge = store.badgeImage != nil
                    HStack(spacing: 14) {
                        imagePreview(store.badgeImage, fallback: "trophy.fill")
                        Button(hasBadge ? "Replace Badge…" : "Choose Badge…") {
                            imageTarget = .badge; showSourceDialog = true
                        }
                        Spacer()
                        if hasBadge {
                            Button("Remove", role: .destructive) { store.clearBadge() }
                        }
                    }
                } header: {
                    Text("Tournament Badge")
                } footer: {
                    Text("The center scoreboard badge — pick from Photos, the Files app, or the camera. The app ships without an emblem; supply your own image (you're responsible for any rights to it). A trophy symbol is shown until you do.")
                }

                Section {
                    let hasBall = store.ballImage != nil
                    HStack(spacing: 14) {
                        imagePreview(store.ballImage, fallback: "soccerball")
                        Button(hasBall ? "Replace Ball…" : "Choose Ball…") {
                            imageTarget = .ball; showSourceDialog = true
                        }
                        Spacer()
                        if hasBall {
                            Button("Remove", role: .destructive) { store.clearBall() }
                        }
                    }
                } header: {
                    Text("Ball")
                } footer: {
                    Text("The ball shown on the pitch — pick from Photos, the Files app, or the camera. A soccerball symbol is used until you do.")
                }

                Section {
                    Picker("Source", selection: $store.weatherSource) {
                        ForEach(WeatherSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    Picker("Units", selection: $store.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Weather")
                } footer: {
                    Text("WeatherKit is Apple's weather service (provisioned for this app). If it's unavailable on the current device, WC Tracker automatically falls back to Open-Meteo. The active source is shown on the weather card.")
                }

                Section("Match Data") {
                    LabeledContent("Scores, stats & events", value: "ESPN")
                }

                Section {
                    Text("Pitch positions are placed from each team's real formation; the ball is estimated from the play-by-play event feed (no free API provides live positional tracking). Replay mode steps through a finished 2026 match's real event timeline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About the pitch")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(imageTarget == .ball ? "Ball Image" : "Badge Image",
                                isPresented: $showSourceDialog, titleVisibility: .visible) {
                Button("Photo Library") { showPhotos = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showCamera = true }
                }
                Button("Choose File") { showFileImporter = true }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showPhotos, selection: $badgePick, matching: .images)
            .onChange(of: badgePick) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        applyPickedImage(data)
                    }
                    badgePick = nil
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                // Files returns a security-scoped URL; access it while reading.
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { applyPickedImage(data) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let data = image.pngData() { applyPickedImage(data) }
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder private func imagePreview(_ image: UIImage?, fallback: String) -> some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(width: 34, height: 34)
                .background(Brand.barBlack, in: RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: fallback)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
        }
    }
}

// MARK: - Native camera capture

/// Wraps the system camera (`UIImagePickerController`) so the badge can be taken
/// with the camera, alongside the Photos and Files importers.
private struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
