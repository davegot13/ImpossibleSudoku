import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
    /// A color that switches with light and dark mode, with optional Increase Contrast variants.
    init(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) {
        self.init(uiColor: UIColor { t in
            let hc = t.accessibilityContrast == .high
            if t.userInterfaceStyle == .dark { return UIColor(hex: hc ? (darkHC ?? dark) : dark) }
            return UIColor(hex: hc ? (lightHC ?? light) : light)
        })
    }
}

/// One meaning per color. Coral: brand, focus digit, active tool. Ring: selection. Red: error and cross-out.
/// Mint: hints. Gold: completion and records.
enum Palette {
    // Ground (the "cabinet")
    static let ground = Color(light: 0x2E3192, dark: 0x13143A)
    static let groundDeep = Color(light: 0x24277A, dark: 0x0B0C26)
    static let surface = Color(light: 0x3F429F, dark: 0x1E1F48)
    static let surfacePressed = Color(light: 0x4A4DAA, dark: 0x272958)
    static let hairline = Color.white.opacity(0.10)
    static let onGround = Color.white
    static let onGround2 = Color(light: 0xC9CBFF, dark: 0xB4B7F2)
    static let onGround3 = Color(light: 0xA9ABE6, dark: 0x8A8DD6)

    // Paper (board, keys, sheets)
    static let paper = Color(light: 0xFFFDF7, dark: 0x1D1F4F)
    /// The brand mark's tiles stay light in both schemes, like the app icon.
    static let markTile = Color(light: 0xFFFDF7, dark: 0xE4E2F4)
    static let paper2 = Color(light: 0xF1EFF8, dark: 0x282A5E)
    static let gridLine = Color(light: 0xDCDBEA, dark: 0x2E3168, lightHC: 0xB9B8D4, darkHC: 0x4A4E95)
    static let ink = Color(light: 0x1B1C3A, dark: 0xECEBFF)
    static let ink2 = Color(light: 0x55577A, dark: 0xB4B6E0)
    static let pencil = Color(light: 0x343BC9, dark: 0xA4AAFF, lightHC: 0x262CA8, darkHC: 0xC4C8FF)
    static let note = Color(light: 0x5D6088, dark: 0xB0B2DC, lightHC: 0x1B1C3A, darkHC: 0xECEBFF)
    static let peer = Color(light: 0xEEEEF9, dark: 0x262960, lightHC: 0xE3E4F7, darkHC: 0x30347A)
    static let selectFill = Color(light: 0xFFE8A3, dark: 0x3A3D85)
    static let selectRing = Color(light: 0x2E3192, dark: 0xFFC94A)
    static let candidate = Color(light: 0xFFE2D6, dark: 0x55304C)
    static let focusFill = Color(hex: 0xF2532F)
    static let badge = Color(hex: 0xD93D1C)
    static let slash = Color(light: 0xE62E3D, dark: 0xFF5A64)
    static let error = Color(light: 0xD7262B, dark: 0xFF6A72)
    static let errorFill = Color(light: 0xFFD9D6, dark: 0x5A2236)
    static let hint = Color(light: 0x0E8A6C, dark: 0x2FD4A7)
    static let hintFill = Color(light: 0xD9F5EC, dark: 0x1E4A55)

    // Keys
    static let keyFace = Color(light: 0xFFFDF7, dark: 0x2A2C66)
    static let keyFaceNotes = Color(light: 0xE7E8FB, dark: 0x23265C)
    static let keyLip = Color(light: 0x1F2170, dark: 0x08091F)

    // Brand
    static let coral = Color(hex: 0xFF5D3A)
    /// Coral dark enough for white text at body sizes (4.5:1).
    static let action = Color(hex: 0xD93D1C)
    static let actionPressed = Color(hex: 0xBF3313)
    static let gold = Color(hex: 0xFFC94A)
    static let goldInk = Color(hex: 0x1B1C3A)

    static var groundGradient: LinearGradient {
        LinearGradient(colors: [ground, groundDeep], startPoint: .top, endPoint: .bottom)
    }
}

/// Type scale. Chrome uses text styles so Dynamic Type works; board, pad and score sizes come from geometry.
enum Typo {
    static func r(_ s: Font.TextStyle, _ w: Font.Weight) -> Font { .system(s, design: .rounded, weight: w) }
    static let wordmark = Font.system(size: 40, weight: .black, design: .rounded)
    static let scoreHero = Font.system(size: 52, weight: .black, design: .rounded).monospacedDigit()
    static let title = r(.title, .bold)
    static let title2 = r(.title2, .bold)
    static let headline = r(.headline, .semibold)
    static let body = r(.body, .regular)
    static let callout = r(.subheadline, .medium)
    static let footnote = r(.footnote, .medium)
    static let eyebrow = r(.caption2, .bold)
    static let timer = r(.headline, .semibold).monospacedDigit()
}

extension Font {
    /// Fixed-size rounded font, for geometry-driven sizes (board, pad, score).
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Small uppercase section label.
    func eyebrowStyle(_ color: Color = Palette.onGround3) -> some View {
        self.font(Typo.eyebrow).textCase(.uppercase).tracking(0.9).foregroundStyle(color)
    }
}

enum Motion {
    static let press = Animation.easeOut(duration: 0.12)
    static let select = Animation.snappy(duration: 0.16)
    static let pop = Animation.spring(response: 0.30, dampingFraction: 0.55)
    static let settle = Animation.smooth(duration: 0.35)
    static let sheet = Animation.spring(response: 0.45, dampingFraction: 0.86)
    static let count = Animation.easeOut(duration: 0.45)
    static let fade = Animation.easeInOut(duration: 0.15)
    static func pick(_ a: Animation, _ reduce: Bool) -> Animation { reduce ? fade : a }
}

enum Metrics {
    static let cardRadius: CGFloat = 20
    static let sheetRadius: CGFloat = 28
    static let keyRadius: CGFloat = 12
    static let toolRadius: CGFloat = 14
}

/// Settings stored in UserDefaults and read with @AppStorage.
enum SettingsKey {
    static let appearance = "appearance"      // 0 system, 1 light, 2 dark
    static let haptics = "haptics"
    static let controlsLeading = "controlsLeading"
    static let seenHowTo = "seenHowTo"
    static let tipNotesDrag = "tipNotesDrag"
}

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()

    static var enabled: Bool { UserDefaults.standard.object(forKey: SettingsKey.haptics) as? Bool ?? true }

    static func handle(_ e: GameEvent) {
        guard enabled else { return }
        switch e {
        case .select: selection.selectionChanged()
        case .note: soft.impactOccurred(intensity: 0.45)
        case let .placed(_, _, _, combo, revealed):
            if revealed { light.impactOccurred(intensity: 0.5) }
            else if combo >= 5 { rigid.impactOccurred(intensity: 1.0) }
            else if combo >= 2 { medium.impactOccurred(intensity: 0.5 + 0.1 * CGFloat(combo)) }
            else { light.impactOccurred(intensity: 0.6) }
        case .unitComplete: soft.impactOccurred(intensity: 0.8)
        case .digitComplete: rigid.impactOccurred(intensity: 0.7)
        case .mistake: notify.notificationOccurred(.error)
        case .hint: soft.impactOccurred(intensity: 0.5)
        case .solved:
            notify.notificationOccurred(.success)
            for k in 1...3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(k)) { light.impactOccurred(intensity: 0.5) }
            }
        case .newBest: notify.notificationOccurred(.success)
        case .runOver: heavy.impactOccurred(intensity: 1.0)
        case .pause: light.impactOccurred(intensity: 0.4)
        }
    }

    static func prepare() { light.prepare(); selection.prepare() }
}

/// VoiceOver announcements for game events.
enum Announcer {
    static func say(_ text: String, high: Bool = false) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    static func handle(_ e: GameEvent) {
        switch e {
        case let .placed(_, d, pts, combo, revealed):
            say(revealed ? "Revealed \(d)." : "Correct. Plus \(pts)." + (combo > 1 ? " Combo times \(combo)." : ""))
        case let .mistake(_, h):
            say("Wrong digit. " + (h == 0 ? "No hearts left." : h == 1 ? "1 heart left." : "\(h) hearts left."), high: true)
        case let .digitComplete(d): say("All \(d)s placed.")
        case .unitComplete: break
        default: break
        }
    }
}
