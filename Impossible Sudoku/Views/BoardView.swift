import SwiftUI

enum CellFocus: Equatable { case none, placed, candidate, dim }

/// Geometry of the "nine paper tiles" board: 3x3 boxes separated by gutters that show the ground.
struct BoardGeometry {
    let side: CGFloat
    let gutter: CGFloat
    let outerRadius: CGFloat

    var box: CGFloat { (side - 2 * gutter) / 3 }
    var cell: CGFloat { box / 3 }

    func boxOrigin(_ b: Int) -> CGPoint {
        CGPoint(x: CGFloat(b % 3) * (box + gutter), y: CGFloat(b / 3) * (box + gutter))
    }

    func center(_ i: Int) -> CGPoint {
        let r = Sudoku.row[i], c = Sudoku.col[i]
        return CGPoint(x: CGFloat(c / 3) * (box + gutter) + (CGFloat(c % 3) + 0.5) * cell,
                       y: CGFloat(r / 3) * (box + gutter) + (CGFloat(r % 3) + 0.5) * cell)
    }

    /// Touches in a gutter snap to the nearest cell, so drags across boxes never drop out.
    func index(at p: CGPoint) -> Int? {
        func axis(_ v: CGFloat) -> Int? {
            guard v >= -gutter, v < side + gutter else { return nil }
            let v = min(max(v, 0), side - 0.01)
            var b = min(2, Int(v / (box + gutter)))
            var within = v - CGFloat(b) * (box + gutter)
            if within >= box {
                if within - box > gutter / 2 && b < 2 { b += 1; within = 0 } else { within = box - 0.01 }
            }
            return b * 3 + min(2, max(0, Int(within / cell)))
        }
        guard let c = axis(p.x), let r = axis(p.y) else { return nil }
        return r * 9 + c
    }

    func tileRect(_ b: Int) -> CGRect {
        let o = boxOrigin(b)
        return CGRect(x: o.x, y: o.y, width: box, height: box)
    }

    func tileShape(_ b: Int) -> UnevenRoundedRectangle {
        let bx = b % 3, by = b / 3, R = outerRadius, r: CGFloat = 3
        return UnevenRoundedRectangle(topLeadingRadius: bx == 0 && by == 0 ? R : r,
                                      bottomLeadingRadius: bx == 0 && by == 2 ? R : r,
                                      bottomTrailingRadius: bx == 2 && by == 2 ? R : r,
                                      topTrailingRadius: bx == 2 && by == 0 ? R : r,
                                      style: .continuous)
    }
}

/// The nine tiles as one shape (fill and mask).
struct TilesShape: Shape {
    let g: BoardGeometry
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for b in 0..<9 { p.addPath(g.tileShape(b).path(in: g.tileRect(b))) }
        return p
    }
}

/// 1pt rules between cells inside each box.
struct HairlinesShape: Shape {
    let g: BoardGeometry
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for b in 0..<9 {
            let o = g.boxOrigin(b)
            for k in 1...2 {
                let x = o.x + CGFloat(k) * g.cell
                p.move(to: CGPoint(x: x, y: o.y)); p.addLine(to: CGPoint(x: x, y: o.y + g.box))
                let y = o.y + CGFloat(k) * g.cell
                p.move(to: CGPoint(x: o.x, y: y)); p.addLine(to: CGPoint(x: o.x + g.box, y: y))
            }
        }
        return p
    }
}

struct BoardView: View {
    @EnvironmentObject var store: GameStore
    let game: GameState
    let side: CGFloat
    let gutter: CGFloat
    let outerRadius: CGFloat
    @State var dragStart: CGPoint? = nil
    @GestureState var dragActive = false
    @Environment(\.colorScheme) var scheme
    @Namespace var rotorNS

    private var g: BoardGeometry { BoardGeometry(side: side, gutter: gutter, outerRadius: outerRadius) }

    var body: some View {
        let geo = g
        let focus = store.focusDigit
        let fb = focus > 0 ? Sudoku.bit(focus) : 0
        let multi = store.selection.count > 1
        let p = store.primary
        let hidden = store.paused
        let isRunOver: Bool = { if case .runOver? = store.overlay { return true }; return false }()
        let flash = store.unitFlash
        let pulse = store.digitPulse
        let wrong = store.wrongEntry

        ZStack(alignment: .topLeading) {
            TilesShape(g: geo).fill(Palette.paper)

            // Full-bleed layer: peers and completed-unit sweeps.
            ZStack(alignment: .topLeading) {
                ForEach(0..<81, id: \.self) { i in
                    CellBackground(peer: !hidden && isPeerHighlight(i, primary: p, multi: multi),
                                   flashActive: flash?.cells.contains(i) ?? false,
                                   flashToken: flash?.token ?? 0,
                                   flashDelay: flashDelay(i, flash))
                        .frame(width: geo.cell, height: geo.cell)
                        .position(geo.center(i))
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .mask(TilesShape(g: geo))
            .accessibilityHidden(true)

            HairlinesShape(g: geo).stroke(Palette.gridLine, lineWidth: 1).accessibilityHidden(true)

            // Chips and content.
            ForEach(0..<81, id: \.self) { i in
                makeCell(i, cell: geo.cell, focus: focus, fb: fb, hidden: hidden, wrong: wrong, pulse: pulse)
                .equatable()
                .frame(width: geo.cell, height: geo.cell)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Row \(Sudoku.row[i] + 1), column \(Sudoku.col[i] + 1)")
                .accessibilityValue(cellValue(i))
                .accessibilityAddTraits(store.selection.contains(i) ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(store.notesMode ? "Double-tap to add to or remove from the selection." : "Double-tap to select.")
                .accessibilityAction { store.tapCell(i) }
                .accessibilityActions { digitActions(i) }
                .accessibilityRotorEntry(id: i, in: rotorNS)
                .position(geo.center(i))
            }

            ForEach(store.pops) { pop in
                ScoreChip(pop: pop)
                    .position(x: geo.center(pop.cell).x, y: geo.center(pop.cell).y - geo.cell * 0.5)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .blur(radius: hidden ? 6 : 0)
        .saturation(isRunOver ? 0 : 1)
        .brightness(isRunOver ? -0.06 : 0)
        .animation(.easeOut(duration: 0.6), value: isRunOver)
        .compositingGroup()
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.28), radius: 18, y: 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($dragActive) { _, state, _ in state = true }
                .onChanged { v in
                    guard let i = geo.index(at: v.location) else { return }
                    // A new start point means a new touch, even if the last one was cancelled.
                    if dragStart != v.startLocation { dragStart = v.startLocation; store.touchBegan(i) }
                    else { store.touchMoved(i) }
                }
                .onEnded { _ in
                    dragStart = nil
                    store.touchEnded()
                }
        )
        .onChange(of: dragActive) { _, active in
            if !active { dragStart = nil; store.touchEnded() }   // also runs when the system cancels the drag
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sudoku board")
        .accessibilityRotor("Empty cells") {
            ForEach((0..<81).filter { game.vals[$0] == 0 }, id: \.self) { i in
                AccessibilityRotorEntry("Row \(Sudoku.row[i] + 1), column \(Sudoku.col[i] + 1)", id: i, in: rotorNS)
            }
        }
        .accessibilityRotor("Selected cells") {
            ForEach(store.selection.sorted(), id: \.self) { i in
                AccessibilityRotorEntry("Row \(Sudoku.row[i] + 1), column \(Sudoku.col[i] + 1)", id: i, in: rotorNS)
            }
        }
    }

    private func makeCell(_ i: Int, cell: CGFloat, focus: Int, fb: Int, hidden: Bool, wrong: WrongEntry?, pulse: DigitPulse?) -> CellView {
        let isWrong = wrong?.cell == i
        let wrongDigit: Int? = isWrong ? wrong?.digit : nil
        let wrongToken: Int = wrong?.token ?? 0   // same for every cell, so clearing never re-triggers the shake
        let pulseActive: Bool = pulse != nil && game.vals[i] == pulse?.digit
        let hintKey: Bool = store.hint?.keyCells.contains(i) ?? false
        let hintTarget: Bool = store.hint?.cell == i
        let waveDelay: Double = 0.035 * Double(Sudoku.row[i] + Sudoku.col[i])
        let pulseDelay: Double = 0.02 * Double(i / 9)
        return CellView(size: cell, value: game.vals[i], given: game.isGiven(i), notes: game.notes[i], cross: game.cross[i],
                        focusDigit: focus, focus: focusState(i, focus: focus, fb: fb), selected: store.selection.contains(i),
                        hintKey: hintKey, hintTarget: hintTarget, wrongDigit: wrongDigit, wrongToken: wrongToken,
                        hidden: hidden, waveToken: store.solveToken, waveDelay: waveDelay,
                        pulseActive: pulseActive, pulseToken: pulse?.token ?? 0, pulseDelay: pulseDelay)
    }

    private func flashDelay(_ i: Int, _ f: UnitFlash?) -> Double {
        guard let f else { return 0 }
        let d = max(abs(Sudoku.row[i] - Sudoku.row[f.origin]), abs(Sudoku.col[i] - Sudoku.col[f.origin]))
        return 0.025 * Double(d)
    }

    private func isPeerHighlight(_ i: Int, primary p: Int, multi: Bool) -> Bool {
        guard !multi, p >= 0, i != p, store.selection.contains(p) else { return false }
        return Sudoku.isPeer[p][i]
    }

    private func focusState(_ i: Int, focus: Int, fb: Int) -> CellFocus {
        guard focus > 0, !store.paused else { return .none }
        if game.vals[i] == focus { return .placed }
        if game.vals[i] == 0 && game.notes[i] & fb != 0 && game.cross[i] & fb == 0 { return .candidate }
        return store.selection.contains(i) ? .none : .dim
    }

    // MARK: Accessibility

    private func list(_ mask: Int) -> String {
        Sudoku.digitsOf[mask].map(String.init).formatted(.list(type: .and))
    }

    private func cellValue(_ i: Int) -> String {
        if store.paused { return "Hidden" }
        var parts: [String] = []
        let v = game.vals[i]
        if v != 0 {
            parts.append(game.isGiven(i) ? "Given \(v)" : "\(v)")
        } else {
            parts.append("Empty")
            let live = game.notes[i] & ~game.cross[i] & 511, crossed = game.notes[i] & game.cross[i]
            if live != 0 { parts.append("Candidates \(list(live))") }
            if crossed != 0 { parts.append("Crossed out \(list(crossed))") }
        }
        if store.hint?.cell == i { parts.append("Hint target") }
        else if store.hint?.keyCells.contains(i) == true { parts.append("Hint pattern cell") }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder private func digitActions(_ i: Int) -> some View {
        if game.vals[i] == 0 {
            ForEach(1...9, id: \.self) { d in
                Button(actionName(i, d)) { store.accessibilityInput(d, at: i) }
            }
        }
    }

    private func actionName(_ i: Int, _ d: Int) -> String {
        guard store.notesMode else { return "Place \(d)" }
        let b = Sudoku.bit(d)
        if game.notes[i] & b == 0 { return "Add note \(d)" }
        return game.cross[i] & b == 0 ? "Cross out \(d)" : "Restore \(d)"
    }
}

/// Full-bleed cell layer under the hairlines: peer tint and the gold completed-unit sweep.
struct CellBackground: View, Equatable {
    let peer: Bool
    let flashActive: Bool
    let flashToken: Int
    let flashDelay: Double
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    nonisolated static func == (a: CellBackground, b: CellBackground) -> Bool {
        a.peer == b.peer && a.flashActive == b.flashActive && a.flashToken == b.flashToken && a.flashDelay == b.flashDelay
    }

    var body: some View {
        ZStack {
            if peer { Palette.peer }
            Palette.gold
                .phaseAnimator([0, 1, 2], trigger: flashToken) { v, phase in
                    v.opacity(phase == 1 && flashActive ? 0.38 : 0)
                } animation: { [rm = reduceMotion, flashDelay] phase in
                    phase == 1 ? .easeOut(duration: 0.12).delay(rm ? 0 : flashDelay) : .easeIn(duration: 0.38)
                }
        }
    }
}

struct CellView: View, Equatable {
    let size: CGFloat
    let value: Int
    let given: Bool
    let notes: Int
    let cross: Int
    let focusDigit: Int
    let focus: CellFocus
    let selected: Bool
    let hintKey: Bool
    let hintTarget: Bool
    let wrongDigit: Int?
    let wrongToken: Int
    let hidden: Bool
    let waveToken: Int
    let waveDelay: Double
    let pulseActive: Bool
    let pulseToken: Int
    let pulseDelay: Double

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.legibilityWeight) var legibility

    nonisolated static func == (a: CellView, b: CellView) -> Bool {
        a.size == b.size && a.value == b.value && a.given == b.given && a.notes == b.notes && a.cross == b.cross
            && a.focusDigit == b.focusDigit && a.focus == b.focus && a.selected == b.selected && a.hintKey == b.hintKey
            && a.hintTarget == b.hintTarget && a.wrongDigit == b.wrongDigit && a.wrongToken == b.wrongToken
            && a.hidden == b.hidden && a.waveToken == b.waveToken && a.pulseActive == b.pulseActive && a.pulseToken == b.pulseToken
    }

    private var chip: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.14, style: .continuous) }

    var body: some View {
        ZStack {
            if !hidden {
                if let fill = chipFill {
                    chip.fill(fill).padding(2)
                }
                content
            }
            // Solve celebration: a diagonal coral wave across every cell.
            chip.fill(Palette.focusFill).padding(2)
                .phaseAnimator([0, 1, 2], trigger: waveToken) { v, phase in
                    v.opacity(phase == 1 && waveToken > 0 ? 0.55 : 0)
                } animation: { [rm = reduceMotion, waveDelay] phase in
                    phase == 1 ? .easeOut(duration: 0.12).delay(rm ? 0 : waveDelay) : .easeIn(duration: 0.30)
                }
                .allowsHitTesting(false)
        }
        .overlay { if !hidden { ring } }
        .keyframeAnimator(initialValue: 0.0, trigger: wrongToken) { [rm = reduceMotion, wrongDigit] v, x in
            v.offset(x: rm || wrongDigit == nil ? 0 : x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-6, duration: 0.06)
                LinearKeyframe(6, duration: 0.07)
                LinearKeyframe(-4, duration: 0.07)
                LinearKeyframe(4, duration: 0.07)
                LinearKeyframe(0, duration: 0.08)
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: pulseToken) { [rm = reduceMotion, pulseActive] v, s in
            v.scaleEffect(pulseActive && !rm ? s : 1)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.0, duration: max(0.001, pulseDelay))
                CubicKeyframe(1.12, duration: 0.12)
                SpringKeyframe(1.0, duration: 0.3)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Motion.pop, value: value)
        .animation(.easeOut(duration: 0.15), value: wrongDigit)
    }

    private var chipFill: Color? {
        if wrongDigit != nil && value == 0 { return Palette.errorFill }
        if hintTarget { return Palette.hintFill }
        if focus == .placed { return Palette.focusFill }
        if selected { return Palette.selectFill }
        if focus == .candidate { return Palette.candidate }
        if hintKey { return Palette.hintFill.opacity(0.6) }
        return nil
    }

    @ViewBuilder var ring: some View {
        if hintTarget {
            chip.strokeBorder(Palette.hint, lineWidth: 2.5).padding(2)
        } else if hintKey {
            chip.strokeBorder(Palette.hint, style: StrokeStyle(lineWidth: 2, dash: [4, 3])).padding(2)
        } else if selected {
            chip.strokeBorder(focus == .placed ? Color.white : Palette.selectRing, lineWidth: 2).padding(2)
        }
    }

    @ViewBuilder var content: some View {
        if value != 0 {
            Text("\(value)")
                .font(.rounded(size * 0.62, given ? .bold : .medium))
                .foregroundStyle(valueColor)
                .opacity(focus == .dim ? 0.45 : 1)
                .offset(y: -size * 0.01)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.4).combined(with: .opacity))
        } else if let w = wrongDigit {
            Text("\(w)")
                .font(.rounded(size * 0.62, .bold))
                .foregroundStyle(Palette.error)
                .transition(.opacity)
        } else if notes != 0 {
            notesGrid
        }
    }

    private var valueColor: Color {
        if focus == .placed { return .white }
        return given ? Palette.ink : Palette.pencil
    }

    private var notesGrid: some View {
        let inset = size * 0.07
        let slot = (size - 2 * inset) / 3
        let bold = legibility == .bold
        return ZStack(alignment: .topLeading) {
            ForEach(1...9, id: \.self) { d in
                if notes & Sudoku.bit(d) != 0 {
                    note(d, slot: slot, bold: bold)
                        .frame(width: slot, height: slot)
                        .position(x: inset + (CGFloat((d - 1) % 3) + 0.5) * slot,
                                  y: inset + (CGFloat((d - 1) / 3) + 0.5) * slot)
                }
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private func note(_ d: Int, slot: CGFloat, bold: Bool) -> some View {
        let b = Sudoku.bit(d)
        let isFocus = d == focusDigit
        let fontSize = size * (bold ? 0.28 : 0.26)
        if cross & b != 0 {
            Text("\(d)")
                .font(.rounded(fontSize, isFocus || bold ? .semibold : .medium)).monospacedDigit()
                .foregroundStyle(isFocus ? Palette.ink : Palette.note)
                .opacity(isFocus ? 1 : (focus == .dim ? 0.45 : 0.8))
                .frame(width: slot, height: slot)
                .overlay(
                    Slash()
                        .stroke(Palette.slash, style: StrokeStyle(lineWidth: max(1.25, size * (isFocus ? 0.055 : 0.045)), lineCap: .round))
                        .padding(slot * 0.14)
                )
        } else if isFocus {
            Text("\(d)")
                .font(.rounded(size * 0.23, .bold)).monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: size * 0.30, height: size * 0.30)
                .background(Palette.badge, in: RoundedRectangle(cornerRadius: size * 0.08, style: .continuous))
        } else {
            Text("\(d)")
                .font(.rounded(fontSize, bold ? .semibold : .medium)).monospacedDigit()
                .foregroundStyle(Palette.note)
                .opacity(focus == .dim ? 0.35 : (focus == .candidate ? 0.6 : 1))
        }
    }
}

/// Diagonal stroke from bottom-left to top-right.
struct Slash: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// Floating score feedback: "+480 ×3", "−250", "−300".
struct ScoreChip: View {
    let pop: ScorePop
    @State var go = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private var fill: Color {
        switch pop.kind {
        case .points: Palette.badge
        case .penalty: Palette.error
        case .hint: Palette.hint
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(pop.text)
            if pop.kind == .points && pop.combo > 1 {
                Text("×\(pop.combo)").foregroundStyle(Palette.gold)
            }
        }
        .font(.rounded(13, .heavy)).monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(fill, in: Capsule())
        .fixedSize()
        .scaleEffect(go || reduceMotion ? 1 : 0.6)
        .offset(y: go && !reduceMotion ? -28 : 0)
        .opacity(go ? 0 : 1)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(Motion.pop) { go = false }
            withAnimation(.easeOut(duration: 0.85)) { go = true }
        }
    }
}
