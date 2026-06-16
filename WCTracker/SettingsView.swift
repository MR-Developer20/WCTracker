import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MatchCenterStore
    @Environment(\.dismiss) private var dismiss

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
                    Picker("Source", selection: $store.weatherSource) {
                        ForEach(WeatherSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
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
        }
    }
}
