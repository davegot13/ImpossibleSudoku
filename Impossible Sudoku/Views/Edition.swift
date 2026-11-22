import SwiftUI
#if APPCLIP
import StoreKit
import UIKit
#endif

/// The App Clip target compiles this same code with the APPCLIP condition set.
/// The clip plays the Hard tier; Expert and Nightmare point to the full app.
enum Edition {
    #if APPCLIP
    static let isClip = true
    #else
    static let isClip = false
    #endif

    static func isLocked(_ tier: Tier) -> Bool { isClip && tier != .hard }
}

#if APPCLIP
/// Presents and dismisses the system App Store banner for the full app.
/// Driven directly through SKOverlay so that leaving a screen reliably takes the banner down.
final class FullAppOverlay: NSObject, SKOverlayDelegate {
    static let shared = FullAppOverlay()
    var onDismiss: (() -> Void)?

    private var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    func set(_ shown: Bool) {
        guard let scene else { return }
        if shown {
            let overlay = SKOverlay(configuration: SKOverlay.AppClipConfiguration(position: .bottom))
            overlay.delegate = self
            overlay.present(in: scene)
        } else {
            SKOverlay.dismiss(in: scene)
        }
    }

    /// Called when the player swipes the banner away, so the next request shows it again.
    func storeOverlayDidFinishDismissal(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        DispatchQueue.main.async { self.onDismiss?() }
    }
}
#endif

extension View {
    /// Shows the App Store banner for the full app while `isPresented` is true (App Clip only; does nothing in the app).
    @ViewBuilder
    func fullAppOverlay(isPresented: Binding<Bool>) -> some View {
        #if APPCLIP
        onChange(of: isPresented.wrappedValue) { _, shown in
            FullAppOverlay.shared.onDismiss = {
                if isPresented.wrappedValue { isPresented.wrappedValue = false }
            }
            FullAppOverlay.shared.set(shown)
        }
        #else
        self
        #endif
    }
}
