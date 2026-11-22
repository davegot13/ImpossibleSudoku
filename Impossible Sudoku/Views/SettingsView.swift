import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) var dismiss
    @AppStorage(SettingsKey.appearance) var appearance = 0
    @AppStorage(SettingsKey.haptics) var haptics = true
    @AppStorage(SettingsKey.controlsLeading) var controlsLeading = false
    @State var confirmReset = false
    /// iPad and the iPhone Duo inner display have a landscape layout with a side panel.
    var showControlsSide = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Palette.surface)
                } header: {
                    Text("Appearance")
                }

                Section {
                    Toggle("Haptics", isOn: $haptics)
                        .listRowBackground(Palette.surface)
                    if showControlsSide {
                        Picker("Controls in landscape", selection: $controlsLeading) {
                            Text("Right").tag(false)
                            Text("Left").tag(true)
                        }
                        .listRowBackground(Palette.surface)
                    }
                } header: {
                    Text("Feel")
                }

                Section {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.showHowTo = true }
                    } label: {
                        Label("How to play", systemImage: "questionmark.circle")
                    }
                    .listRowBackground(Palette.surface)
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("Reset statistics", systemImage: "arrow.counterclockwise")
                    }
                    .listRowBackground(Palette.surface)
                }

                Section {
                    LabeledContent("Version", value: version)
                        .listRowBackground(Palette.surface)
                    LabeledContent("Puzzles", value: "4,500, each with one solution")
                        .listRowBackground(Palette.surface)
                } header: {
                    Text("About")
                } footer: {
                    Text("Ratings come from a solver that uses human techniques. The hardest technique a puzzle needs sets its rating.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.groundGradient.ignoresSafeArea())
            .foregroundStyle(Palette.onGround)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.ground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .alert("Reset statistics?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { store.resetStatistics() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Best runs, fastest times, solved counts and best combos for every tier are cleared. Your current run is kept.")
            }
        }
        .tint(Palette.coral)
        .environment(\.colorScheme, .dark)
    }
}
