import SwiftUI

@main
struct ImpossibleSudokuApp: App {
    @StateObject var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear {
                    if !store.bankLoaded, let url = Bundle.main.url(forResource: "bank", withExtension: "json") {
                        store.loadBank(from: url)
                    }
                    store.onEvent = { e in
                        Haptics.handle(e)
                        Announcer.handle(e)
                    }
                    Haptics.prepare()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(SettingsKey.appearance) var appearance = 0
    @Environment(\.horizontalSizeClass) var hSize
    @Environment(\.verticalSizeClass) var vSize

    private var scheme: ColorScheme? {
        switch appearance { case 1: .light; case 2: .dark; default: nil }
    }

    var body: some View {
        ZStack {
            Palette.groundGradient.ignoresSafeArea()
            Group {
                switch store.screen {
                case .home:
                    HomeView().transition(.opacity)
                case .game:
                    GameView().transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .accessibilityHidden(store.overlay != nil)

            if let overlay = store.overlay {
                OverlayView(overlay: overlay)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(Motion.settle, value: store.screen)
        .animation(.easeOut(duration: 0.2), value: store.overlay != nil)
        .preferredColorScheme(scheme)
        .sheet(isPresented: $store.showSettings) {
            SettingsView(showControlsSide: hSize == .regular && vSize == .regular).environmentObject(store)
        }
        .fullScreenCover(isPresented: $store.showHowTo) {
            HowToPlayView().environmentObject(store).preferredColorScheme(scheme)
        }
        .fullAppOverlay(isPresented: $store.showFullApp)
        .onChange(of: scenePhase) { _, phase in
            store.appActive = phase == .active
            if phase == .background { store.appWentToBackground() }
            else if phase != .active { store.save() }
        }
    }
}
