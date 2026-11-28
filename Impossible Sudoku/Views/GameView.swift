import SwiftUI

/// Sizes for the game screen, from the available space.
///
/// Three families:
/// - phone: compact width (every iPhone, the iPhone Duo outer display, narrow iPad windows);
/// - roomy portrait: regular width and height in portrait (iPad, iPhone Duo inner display held upright);
/// - roomy landscape: board beside a control panel (iPad, iPhone Duo inner display held sideways).
///   When the height is short (the Duo inner display is 626 to 669 points tall in landscape),
///   the header moves into the panel so the board can use the full height.
struct GameLayout {
    let size: CGSize
    /// Regular width and height: iPad, or the iPhone Duo inner display.
    let roomy: Bool
    /// Key size forced by a fold-aware layout.
    var keyOverride: CGFloat? = nil

    var isPad: Bool { roomy }
    var landscape: Bool { roomy && size.width >= 700 && size.width > size.height * 1.05 }
    var sideHeader: Bool { landscape && size.height < 760 }
    /// Roomy but not iPad sized, like the iPhone Duo inner display in portrait.
    var snug: Bool { roomy && size.height < 1000 }

    /// Short phone screens use a one-row header. A screen whose board is held back by its width,
    /// like the iPhone Duo outer display, keeps the regular header because the height is there.
    var compact: Bool {
        guard !roomy else { return false }
        let regularBoard = size.height - 108 - (52 + 8 + 60) - 28
        return regularBoard < (size.width - 2 * (size.width < 390 ? 8 : 12)) * 0.92
    }
    var tall: Bool { !roomy && size.height >= 760 }
    var margin: CGFloat { roomy ? (sideHeader || size.width < 720 ? 16 : 32) : (size.width < 390 ? 8 : 12) }
    var gutter: CGFloat { roomy ? 5 : 3 }
    var outerRadius: CGFloat { roomy ? 18 : 14 }
    var headerH: CGFloat { compact ? 56 : (roomy && !snug ? 120 : 108) }
    var toolH: CGFloat { roomy ? (snug ? 56 : 60) : compact ? 46 : tall ? 56 : 52 }
    var baseKeyH: CGFloat { roomy ? (snug ? 68 : 80) : compact ? 54 : tall ? 64 : 60 }
    /// Keys grow into spare height on tall phones instead of leaving a gap above the tools.
    var keyBonus: CGFloat {
        guard !roomy else { return 0 }
        let spare = size.height - headerH - basePortraitBoard - (toolH + toolGap + baseKeyH) - 8
        return min(18, max(0, (spare - 56) * 0.5))
    }
    var keyH: CGFloat {
        if let k = keyOverride { return k }
        if landscape { return panelKey }
        return baseKeyH + keyBonus
    }
    var keySpacing: CGFloat { roomy ? 8 : compact ? 4 : 5 }
    var padDigit: CGFloat { roomy ? (snug ? 32 : 36) : compact ? 26 : tall ? 31 : 29 }
    var toolGap: CGFloat { compact ? 6 : tall ? 10 : 8 }
    var controlsH: CGFloat { toolH + toolGap + keyH }
    var column: CGFloat { roomy ? min(size.width - 2 * margin, 860) : size.width - 2 * margin }

    private var basePortraitBoard: CGFloat {
        max(220, min(column, size.height - headerH - (toolH + toolGap + baseKeyH) - 28, roomy ? 900 : 620))
    }
    var portraitBoard: CGFloat {
        max(220, min(column, size.height - headerH - controlsH - 28, roomy ? 900 : 620))
    }

    // Landscape: board plus a side panel with a 3x3 pad.
    var panelGap: CGFloat { sideHeader ? 24 : 32 }
    private var sideAvail: CGFloat { size.width - 2 * margin - panelGap }
    private var sideBoard: CGFloat { max(260, min(size.height - 24, sideAvail - 264, 900)) }
    var panelW: CGFloat {
        if sideHeader { return min(400, sideAvail - sideBoard) }
        return min(max(size.width * 0.30, 320), 400)
    }
    /// Header height inside the side panel.
    var sideHeaderH: CGFloat { 148 }
    var panelSpacing: CGFloat { 10 }
    var panelKey: CGFloat {
        if let k = keyOverride { return k }
        let byWidth = (panelW - 2 * panelSpacing) / 3
        guard sideHeader else { return byWidth }
        let byHeight = (sideBoard - sideHeaderH - 16 - toolH - toolGap - 2 * panelSpacing) / 3
        return max(52, min(byWidth, byHeight))
    }
    var landscapeBoard: CGFloat {
        if sideHeader { return sideBoard }
        return max(260, min(size.height - headerH - 48, size.width - 64 - 32 - panelW, 900))
    }
}

struct GameView: View {
    @EnvironmentObject var store: GameStore
    @AppStorage(SettingsKey.controlsLeading) var controlsLeading = false
    @FocusState var keyboardFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let L = GameLayout(size: geo.size, roomy: min(geo.size.width, geo.size.height) >= 560)
            if let run = store.shownRun {
                if L.roomy, let fold = Fold.region(in: geo) {
                    foldLayout(run, L, fold)
                } else if L.landscape {
                    landscape(run, L)
                } else {
                    portrait(run, L)
                }
            }
        }
        // A tap on empty background lets go of the selection and the highlight. The board and every button answer first.
        .contentShape(Rectangle())
        .onTapGesture { store.clearAll() }
        .focusable()
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .accessibilityElement(children: .contain)
        .onAppear { keyboardFocused = true }
        .onChange(of: store.overlay == nil) { _, clear in if clear { keyboardFocused = true } }
        .onChange(of: store.showSettings || store.showHowTo) { _, open in if !open { keyboardFocused = true } }
        .accessibilityAction(.magicTap) { store.toggleNotes() }
        .accessibilityAction(.escape) {
            if store.hintCardOpen { store.closeHintCard() } else { store.clearSelection() }
        }
    }

    private func portrait(_ run: RunState, _ L: GameLayout) -> some View {
        let board = L.portraitBoard
        let slack = max(0, L.size.height - L.headerH - board - L.controlsH - 8)
        // The hint card may rise from the controls into the gap under the board, stopping just short of the board.
        let gapBelowBoard = max(10, slack + 4 - max(6, slack * 0.5))
        let hintRoom = L.controlsH + gapBelowBoard - 6
        // Short phones (iPhone SE, the Duo's outer screen) leave the card room for about one line of text.
        // While the card is open there, the header folds to its one-row form and the board moves up,
        // which hands the card the 52 points the second header row was using.
        let foldHeader = store.hintCardOpen && store.hint != nil && !L.compact && !L.roomy && hintRoom < 200
        let headerH: CGFloat = foldHeader ? 56 : L.headerH
        return VStack(spacing: 0) {
            GameHeader(run: run, compact: L.compact || foldHeader, isPad: L.isPad)
                .frame(width: board, height: headerH)
            Spacer(minLength: 6).frame(maxHeight: max(6, slack * 0.5))
            BoardView(game: run.game, side: board, gutter: L.gutter, outerRadius: L.outerRadius)
                .frame(width: board, height: board)
            Spacer(minLength: 10)
            ControlsView(layout: L, padColumns: 9, hintRoom: hintRoom + (L.headerH - headerH))
                .frame(width: board, height: L.controlsH, alignment: .bottom)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.sheet, value: foldHeader)
    }

    @ViewBuilder
    private func landscape(_ run: RunState, _ L: GameLayout) -> some View {
        if L.sideHeader { sideLandscape(run, L) } else { padLandscape(run, L) }
    }

    /// Tall landscape (iPad): header across the top, board beside the panel.
    private func padLandscape(_ run: RunState, _ L: GameLayout) -> some View {
        let board = L.landscapeBoard
        let total = board + L.panelGap + L.panelW
        let panel = ControlsView(layout: L, padColumns: 3)
            .frame(width: L.panelW, height: L.toolH + L.toolGap + 3 * L.panelKey + 2 * L.panelSpacing)
        return VStack(spacing: 16) {
            GameHeader(run: run, compact: false, isPad: true)
                .frame(width: total, height: L.headerH)
            HStack(spacing: L.panelGap) {
                if controlsLeading { panel }
                BoardView(game: run.game, side: board, gutter: L.gutter, outerRadius: L.outerRadius)
                    .frame(width: board, height: board)
                if !controlsLeading { panel }
            }
            .frame(width: total)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// Short landscape (iPhone Duo inner display): the board takes the full height and
    /// the header sits at the top of the side panel.
    private func sideLandscape(_ run: RunState, _ L: GameLayout) -> some View {
        let board = L.landscapeBoard
        let controlsH = L.toolH + L.toolGap + 3 * L.panelKey + 2 * L.panelSpacing
        let panel = VStack(spacing: 0) {
            GameHeader(run: run, compact: false, isPad: true, stacked: true)
                .frame(height: L.sideHeaderH, alignment: .top)
            Spacer(minLength: 16)
            ControlsView(layout: L, padColumns: 3)
                .frame(height: controlsH)
        }
        .frame(width: L.panelW, height: board)
        return HStack(spacing: L.panelGap) {
            if controlsLeading { panel }
            BoardView(game: run.game, side: board, gutter: L.gutter, outerRadius: L.outerRadius)
                .frame(width: board, height: board)
            if !controlsLeading { panel }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Partly open iPhone Duo: nothing sits across the fold.
    /// Book (fold runs top to bottom): board on one half, header and pad on the other.
    /// Laptop (fold runs side to side): board on the upright half, header and pad on the flat half.
    @ViewBuilder
    private func foldLayout(_ run: RunState, _ L: GameLayout, _ fold: CGRect) -> some View {
        let w = L.size.width, h = L.size.height, m: CGFloat = 16
        if fold.height >= fold.width {
            let leftW = max(0, fold.minX), rightW = max(0, w - fold.maxX)
            let boardSide = controlsLeading ? rightW : leftW
            let panelSide = controlsLeading ? leftW : rightW
            let board = max(220, min(boardSide - 2 * m, h - 24, 760))
            let panelW = max(220, min(400, panelSide - 2 * m))
            let LL = foldLayoutModel(L, padWidth: panelW, padHeight: h - 24 - L.sideHeaderH - 16)
            let controlsH = L.toolH + L.toolGap + 3 * LL.panelKey + 2 * L.panelSpacing
            let panel = VStack(spacing: 0) {
                GameHeader(run: run, compact: false, isPad: true, stacked: true)
                    .frame(height: L.sideHeaderH, alignment: .top)
                Spacer(minLength: 16)
                ControlsView(layout: LL, padColumns: 3)
                    .frame(height: controlsH)
            }
            .frame(width: panelW, height: min(h - 24, max(board, L.sideHeaderH + 16 + controlsH)))
            let boardView = BoardView(game: run.game, side: board, gutter: L.gutter, outerRadius: L.outerRadius)
                .frame(width: board, height: board)
            HStack(spacing: 0) {
                Group { if controlsLeading { panel } else { boardView } }
                    .frame(width: leftW)
                Color.clear.frame(width: fold.width)
                Group { if controlsLeading { boardView } else { panel } }
                    .frame(width: rightW)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let topH = max(0, fold.minY), bottomH = max(0, h - fold.maxY)
            let column = min(L.column, 680)
            let board = max(220, min(column, topH - 24, 760))
            let padW = min(340, (column - 24) * 0.52)
            let LL = foldLayoutModel(L, padWidth: padW, padHeight: bottomH - 24)
            let controlsH = L.toolH + L.toolGap + 3 * LL.panelKey + 2 * L.panelSpacing
            VStack(spacing: 0) {
                BoardView(game: run.game, side: board, gutter: L.gutter, outerRadius: L.outerRadius)
                    .frame(width: board, height: board)
                    .frame(maxWidth: .infinity)
                    .frame(height: topH)
                Color.clear.frame(height: fold.height)
                HStack(alignment: .top, spacing: 24) {
                    GameHeader(run: run, compact: false, isPad: true, stacked: true)
                        .frame(maxWidth: .infinity, alignment: .top)
                    ControlsView(layout: LL, padColumns: 3)
                        .frame(width: padW, height: controlsH)
                }
                .frame(width: column)
                .frame(maxWidth: .infinity)
                .frame(height: bottomH)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// A layout whose 3x3 pad fits the given space.
    private func foldLayoutModel(_ L: GameLayout, padWidth: CGFloat, padHeight: CGFloat) -> GameLayout {
        var LL = L
        let byWidth = (padWidth - 2 * L.panelSpacing) / 3
        let byHeight = (padHeight - L.toolH - L.toolGap - 2 * L.panelSpacing) / 3
        LL.keyOverride = max(52, min(byWidth, byHeight, 120))
        return LL
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if case .paused? = store.overlay, press.key == .escape || press.key == .space || press.key == .return {
            store.setPaused(false)
            return .handled
        }
        guard store.screen == .game, store.overlay == nil else { return .ignored }
        if press.modifiers.contains(.command) {
            if press.characters.lowercased() == "z" { store.undo(); return .handled }
            return .ignored
        }
        switch press.key {
        case .upArrow: store.moveSelection(dr: -1, dc: 0); return .handled
        case .downArrow: store.moveSelection(dr: 1, dc: 0); return .handled
        case .leftArrow: store.moveSelection(dr: 0, dc: -1); return .handled
        case .rightArrow: store.moveSelection(dr: 0, dc: 1); return .handled
        case .delete, .deleteForward: store.erase(); return .handled
        case .escape:
            if store.hintCardOpen { store.closeHintCard() } else { store.clearSelection() }
            return .handled
        case .space: store.setPaused(true); return .handled
        default: break
        }
        let ch = press.characters.lowercased()
        if let d = Int(ch), (1...9).contains(d) { store.input(d); return .handled }
        switch ch {
        case "n": store.toggleNotes(); return .handled
        case "h": store.requestHint(); return .handled
        default: return .ignored
        }
    }
}

// MARK: - Header

struct GameHeader: View {
    @EnvironmentObject var store: GameStore
    let run: RunState
    let compact: Bool
    let isPad: Bool
    /// Narrow column variant for the side panel in short landscape.
    var stacked = false

    /// During a summary the frozen run already counts the solved puzzle.
    private var puzzleNumber: Int {
        if case .solved? = store.overlay { return max(1, run.solved) }
        return run.solved + 1
    }

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(run.tier.name).font(Typo.headline).foregroundStyle(Palette.onGround)
                        Text("Puzzle \(puzzleNumber) · \(String(format: "%.1f", run.game.rating))")
                            .font(Typo.footnote).foregroundStyle(Palette.gold)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 4)
                    PauseButton()
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        ScoreText(score: run.score, size: 36)
                        StatusLine(run: run, compact: false)
                    }
                    Spacer(minLength: 4)
                    LiveComboRing(clock: store.clock, diameter: 56)
                }
                HStack(spacing: 12) {
                    Hearts(count: run.hearts, size: 16)
                    Spacer(minLength: 4)
                    ClockText(clock: store.clock, frozenTime: store.frozen?.game.elapsed)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        } else if compact {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    ScoreText(score: run.score, size: 28)
                    StatusLine(run: run, compact: true)
                }
                Spacer(minLength: 4)
                Hearts(count: run.hearts, size: 14)
                ClockText(clock: store.clock, frozenTime: store.frozen?.game.elapsed)
                LiveComboRing(clock: store.clock, diameter: 44)
                PauseButton()
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        } else {
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(run.tier.name).font(Typo.headline).foregroundStyle(Palette.onGround)
                        Text("Puzzle \(puzzleNumber) · \(String(format: "%.1f", run.game.rating))")
                            .font(Typo.footnote).foregroundStyle(Palette.gold)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 4)
                    Hearts(count: run.hearts, size: 16)
                    ClockText(clock: store.clock, frozenTime: store.frozen?.game.elapsed)
                    PauseButton()
                }
                .frame(height: 44)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        ScoreText(score: run.score, size: isPad ? 40 : 34)
                        StatusLine(run: run, compact: false)
                    }
                    Spacer(minLength: 4)
                    LiveComboRing(clock: store.clock, diameter: isPad ? 64 : 56)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}

struct ScoreText: View {
    let score: Int
    let size: CGFloat
    var body: some View {
        Text(score, format: .number)
            .font(.rounded(size, .heavy)).monospacedDigit()
            .foregroundStyle(Palette.onGround)
            .contentTransition(.numericText(value: Double(score)))
            .animation(Motion.count, value: score)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel("Score")
            .accessibilityValue(score.formatted())
    }
}

struct StatusLine: View {
    @EnvironmentObject var store: GameStore
    let run: RunState
    let compact: Bool

    var body: some View {
        Group {
            if store.selection.count > 1 {
                HStack(spacing: 8) {
                    Text("\(store.selection.count) cells selected")
                    Button { store.clearSelection() } label: {
                        Text("Clear")
                            .font(Typo.footnote.weight(.semibold))
                            .foregroundStyle(Palette.onGround)
                            .padding(.horizontal, 10)
                            .frame(height: 20)   // no taller than the status line, so the score above never shrinks
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.hairline))
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -12)
                    .accessibilityLabel("Clear selection")
                }
            } else if store.notesMode {
                Label("Notes · tap or drag to pick cells", systemImage: "pencil")
                    .labelStyle(.titleAndIcon)
            } else if compact {
                Text("\(run.tier.name) \(String(format: "%.1f", run.game.rating)) · Puzzle \(store.frozen != nil ? max(1, run.solved) : run.solved + 1)")
            } else {
                // The time to beat, shown while it can still be beaten: the bonus should not be a surprise at the end.
                ParLine(clock: store.clock, par: Rules.par(run.game.rating), frozenTime: store.frozen?.game.elapsed)
            }
        }
        .font(Typo.footnote)
        .foregroundStyle(Palette.onGround2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(minHeight: 20, alignment: .leading)
    }
}

/// "Beat 19:30 for a time bonus", until the time has passed.
struct ParLine: View {
    @ObservedObject var clock: GameClock
    let par: Double
    var frozenTime: Double? = nil
    var body: some View {
        Text((frozenTime ?? clock.elapsed) <= par ? "Beat \(formatTime(par)) for a time bonus" : "No time bonus past \(formatTime(par))")
    }
}

struct Hearts: View {
    let count: Int
    let size: CGFloat
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<Rules.hearts, id: \.self) { k in
                Image(systemName: k < count ? "heart.fill" : "heart")
                    .foregroundStyle(k < count ? Palette.coral : Palette.onGround3)
                    .symbolEffect(.bounce, value: k < count)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hearts")
        .accessibilityValue("\(count) of \(Rules.hearts)")
    }
}

struct ClockText: View {
    @ObservedObject var clock: GameClock
    var frozenTime: Double? = nil
    var body: some View {
        Text(formatTime(frozenTime ?? clock.elapsed))
            .font(Typo.timer)
            .foregroundStyle(Palette.onGround)
            .frame(minWidth: 48, alignment: .trailing)
            .accessibilityLabel("Time")
            .accessibilityValue(Duration.seconds(Int(clock.elapsed)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct PauseButton: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        Button { store.setPaused(true) } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.onGround)
                .frame(width: 44, height: 44)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.hairline))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Pause")
        .accessibilityHint("Opens the menu")
        .accessibilityShowsLargeContentViewer()
    }
}

struct LiveComboRing: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject var clock: GameClock
    let diameter: CGFloat
    var body: some View {
        ComboRing(combo: store.comboShown, fraction: store.comboFraction, diameter: diameter)
    }
}

/// Combo multiplier inside a ring that drains over the 20-second window.
struct ComboRing: View {
    let combo: Int
    let fraction: Double
    var diameter: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private var tint: Color { combo >= 5 ? Palette.gold : combo >= 2 ? Palette.coral : Palette.onGround2 }
    /// The last 5 seconds only matter when there is a combo to lose.
    private var urgent: Bool { combo >= 2 && fraction > 0 && fraction < 0.25 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
            arc
            VStack(spacing: -2) {
                Text("×\(combo)")
                    .font(.rounded(diameter * 0.34, .heavy))
                    .foregroundStyle(combo > 1 ? tint : Palette.onGround3)
                    .contentTransition(.numericText(value: Double(combo)))
                if combo >= 5 && diameter >= 56 {
                    Text("MAX").font(.rounded(10, .heavy)).tracking(0.5).foregroundStyle(Palette.gold)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: combo >= 5 ? Palette.gold.opacity(0.45) : .clear, radius: 8)
        .keyframeAnimator(initialValue: 1.0, trigger: combo) { [rm = reduceMotion] v, s in
            v.scaleEffect(rm ? 1 : s)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.22, duration: 0.10)
                SpringKeyframe(1.0, duration: 0.30)
            }
        }
        .animation(.easeOut(duration: 0.25), value: combo)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Combo")
        .accessibilityValue(combo == 1 ? "times 1" : "times \(combo), \(Int((fraction * Rules.comboWindow).rounded())) seconds left")
    }

    @ViewBuilder var arc: some View {
        let base = Circle()
            .trim(from: 0, to: fraction)
            .stroke(urgent && reduceMotion ? Palette.onGround3 : tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 0.25), value: fraction)
        if urgent && !reduceMotion {
            base.phaseAnimator([1.0, 0.6]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 0.5) }
        } else {
            base
        }
    }
}

/// The iPhone Duo fold.
enum Fold {
    /// The iPhone Duo fold while it's partly open, in this view's coordinates. Nil when flat or closed,
    /// and on every other device.
    static func region(in geo: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            guard let region = geo.reservedRegions(kind: .division).first else { return nil }
            let f = region.frame
            let rect = CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height)
            // The fold runs edge to edge, so it can reach into the safe area along its length.
            // Only its position across the screen has to fall inside this view.
            let vertical = rect.height >= rect.width
            let inside = vertical
                ? rect.minX > 40 && rect.maxX < geo.size.width - 40
                : rect.minY > 40 && rect.maxY < geo.size.height - 40
            return inside ? rect : nil
        }
        return nil
    }
}
