import SwiftUI

struct ControlsView: View {
    @EnvironmentObject var store: GameStore
    let layout: GameLayout
    let padColumns: Int

    private var keyH: CGFloat { padColumns == 3 ? layout.panelKey : layout.keyH }
    private var spacing: CGFloat { padColumns == 3 ? 10 : layout.keySpacing }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: layout.toolGap) {
                HStack(spacing: 4) {
                    ToolButton(title: "Undo", symbol: "arrow.uturn.backward", height: layout.toolH,
                               hint: "Undoes the last change to your notes.") { store.undo() }
                    ToolButton(title: "Erase", symbol: "eraser", height: layout.toolH,
                               hint: "Clears notes in the selected cells.") { store.erase() }
                    ToolButton(title: "Notes", symbol: "pencil", height: layout.toolH, isToggle: true, on: store.notesMode,
                               hint: "When on, digits add, cross out or restore notes.") { store.toggleNotes() }
                    ToolButton(title: "Auto notes", symbol: "wand.and.stars", height: layout.toolH,
                               hint: "Fills every empty cell with its possible digits.") { store.autoNotes() }
                    ToolButton(title: revealMode ? "Reveal" : "Hint", symbol: revealMode ? "eye" : "lightbulb", height: layout.toolH,
                               hint: revealMode ? "Places the digit. Costs \(Rules.revealCost) points." : "Names the next technique. Costs \(Rules.hintCost) points.") {
                        store.requestHint()
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: padColumns), spacing: spacing) {
                    ForEach(1...9, id: \.self) { d in
                        PadKey(digit: d, remaining: store.remaining(d), highlighted: store.focusDigit == d,
                               notesMode: store.notesMode, height: keyH,
                               digitSize: padColumns == 3 ? 36 : layout.padDigit) {
                            store.input(d)
                        }
                    }
                }
            }
            .accessibilityHidden(store.hintCardOpen)

            if store.hintCardOpen, let h = store.hint {
                HintCard(hint: h, minHeight: layout.toolH + layout.toolGap + (padColumns == 3 ? 3 * keyH + 2 * spacing : keyH))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.sheet, value: store.hintCardOpen)
    }

    private var revealMode: Bool {
        if let h = store.hint, h.kind == .place, !store.hintCardOpen { return true }
        return false
    }
}

struct ToolButton: View {
    let title: String
    let symbol: String
    let height: CGFloat
    var isToggle = false
    var on = false
    var hint: String = ""
    let action: () -> Void
    @Environment(\.dynamicTypeSize) var typeSize

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .symbolEffect(.bounce, value: on)
                if !typeSize.isAccessibilitySize {
                    Text(title).font(.rounded(11, .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .foregroundStyle(on ? Color.white : Palette.onGround2)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: Metrics.toolRadius, style: .continuous)
                    .fill(on ? Palette.action : Color.clear)
                    .padding(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolPressStyle())
        .hoverEffect(.highlight)
        .accessibilityLabel(title)
        .accessibilityValue(isToggle ? (on ? "On" : "Off") : "")
        .accessibilityAddTraits(isToggle ? .isToggle : [])
        .accessibilityHint(hint)
        .accessibilityShowsLargeContentViewer()
    }
}

struct ToolPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct PadKey: View {
    let digit: Int
    let remaining: Int
    let highlighted: Bool
    let notesMode: Bool
    let height: CGFloat
    let digitSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("\(digit)")
                    .font(.rounded(notesMode ? digitSize - 4 : digitSize, notesMode ? .medium : .semibold))
                    .foregroundStyle(highlighted ? Color.white : (notesMode ? Palette.note : Palette.pencil))
                Group {
                    if remaining == 0 {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    } else {
                        Text("\(remaining)").font(.rounded(11, .semibold)).monospacedDigit()
                    }
                }
                .foregroundStyle(highlighted ? Color.white.opacity(0.85) : Palette.note.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyStyle(face: highlighted ? Palette.focusFill : (notesMode ? Palette.keyFaceNotes : Palette.keyFace),
                              done: remaining == 0 && !highlighted))
        .frame(height: height)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(digit)")
        .accessibilityValue(remaining == 0 ? "All placed" : "\(remaining) left")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
        .accessibilityHint(notesMode ? "Adds, crosses out or restores this note in the selected cells." : "Places this digit in the selected cell.")
        .accessibilityShowsLargeContentViewer()
    }
}

/// A paper key with a solid lip underneath (no drop shadow on the text).
struct KeyStyle: ButtonStyle {
    let face: Color
    let done: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let drop: CGFloat = done ? 0 : 3
        let sink: CGFloat = pressed ? min(2, drop) : 0
        let shape = RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous)
        return ZStack {
            if !done { shape.fill(Palette.keyLip).offset(y: drop) }
            shape.fill(face).offset(y: sink)
            configuration.label.offset(y: sink)
        }
        .padding(.bottom, drop)
        .opacity(done ? 0.45 : 1)
        .animation(Motion.press, value: pressed)
        .contentShape(Rectangle().inset(by: -2.5))
    }
}

struct HintCard: View {
    @EnvironmentObject var store: GameStore
    let hint: HintInfo
    let minHeight: CGFloat
    @AccessibilityFocusState var focused: Bool

    private var closeTitle: String { hint.kind == .place ? "Got it" : "Keep trying" }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Palette.hint).frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Palette.hint)
                    Text(hint.title).font(Typo.headline).foregroundStyle(Palette.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focused)
                VStack(alignment: .leading, spacing: 6) {
                    Text(hint.body).font(Typo.callout).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if hint.kind == .place {
                        Text(hint.keyCells.subtracting([hint.cell]).isEmpty
                             ? "The outlined cell is the one you can fill."
                             : "Dashed outlines mark the pattern. The solid outline is the cell you can fill.")
                            .font(Typo.footnote).foregroundStyle(Palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button(action: { store.closeHintCard() }) {
                        Text(closeTitle).font(Typo.headline).foregroundStyle(Palette.ink2)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    Button(action: { store.revealHint(hint.cell) }) {
                        Text("Reveal  −\(Rules.revealCost)")
                            .font(Typo.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Palette.action, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(ToolPressStyle())
                    .accessibilityLabel("Reveal the digit, costs \(Rules.revealCost) points")
                }
            }
            .padding(14)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onAppear { focused = true }
    }
}
