import SwiftUI

struct ControlsView: View {
    @EnvironmentObject var store: GameStore
    let layout: GameLayout
    let padColumns: Int
    /// Height the hint card may use, measured up from the bottom of the controls (nil: the controls' own frame).
    var hintRoom: CGFloat? = nil

    private var keyH: CGFloat { padColumns == 3 ? layout.panelKey : layout.keyH }
    private var spacing: CGFloat { padColumns == 3 ? 10 : layout.keySpacing }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: layout.toolGap) {
                HStack(spacing: 4) {
                    ToolButton(title: "Undo", symbol: "arrow.uturn.backward", height: layout.toolH, enabled: store.canUndo,
                               hint: "Undoes the last change to your notes.") { store.undo() }
                    ToolButton(title: "Erase", symbol: "eraser", height: layout.toolH, enabled: store.canErase,
                               hint: "Clears notes in the selected cells.") { store.erase() }
                    ToolButton(title: "Notes", symbol: "pencil", height: layout.toolH, isToggle: true, on: store.notesMode,
                               hint: "When on, digits add, cross out or remove notes.") { store.toggleNotes() }
                    ToolButton(title: "Auto notes", symbol: "wand.and.stars", height: layout.toolH,
                               hint: "Fills every empty cell with its possible digits.") { store.autoNotes() }
                    // The price is on the button before the tap. A hint already paid for opens again for free.
                    ToolButton(title: hintPaid ? "Show hint" : "Hint −\(Rules.hintCost)", symbol: hintPaid ? "lightbulb.fill" : "lightbulb",
                               height: layout.toolH, spokenTitle: hintPaid ? "Show hint" : "Hint",
                               hint: hintPaid ? "Opens the hint you already paid for." : "Names the next technique. Costs \(Rules.hintCost) points.") {
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
            // A tap that lands between two keys does nothing, instead of falling through to the background.
            .contentShape(Rectangle())
            .onTapGesture {}
            .accessibilityHidden(store.hintCardOpen)

            if store.hintCardOpen, let h = store.hint {
                // The card covers the controls and may grow upward into the gap under the board, never past the screen edge.
                // When room is short it first drops the helper line; if the text still doesn't fit, it scrolls and the buttons stay put.
                let cover = layout.toolH + layout.toolGap + (padColumns == 3 ? 3 * keyH + 2 * spacing : keyH)
                let tight = (hintRoom ?? .infinity) < 200
                Color.clear
                    .frame(height: hintRoom.map { max($0, cover) })
                    .overlay(alignment: .bottom) {
                        ViewThatFits(in: .vertical) {
                            HintCard(hint: h, minHeight: cover, tight: tight)
                            HintCard(hint: h, minHeight: cover, tight: tight, helper: false)
                            HintCard(hint: h, minHeight: cover, tight: tight, helper: false, scrolls: true)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.sheet, value: store.hintCardOpen)
    }

    private var hintPaid: Bool { store.hint != nil }
}

struct ToolButton: View {
    let title: String
    let symbol: String
    let height: CGFloat
    var isToggle = false
    var on = false
    /// False when the tool has nothing to act on: it dims and ignores taps.
    var enabled = true
    /// VoiceOver name when the visible title carries extras such as a price.
    var spokenTitle: String? = nil
    var hint: String = ""
    let action: () -> Void
    @Environment(\.dynamicTypeSize) var typeSize

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .symbolEffect(.bounce, value: on)
                    .frame(height: 24)   // one baseline for all five labels, whatever the symbol's height
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
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
        .animation(.easeOut(duration: 0.15), value: enabled)
        .accessibilityLabel(spokenTitle ?? title)
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
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    } else {
                        Text("\(remaining)").font(.rounded(12, .semibold)).monospacedDigit()
                    }
                }
                .frame(height: 14)
                .foregroundStyle(highlighted ? Color.white : Palette.note)
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
        .accessibilityHint(notesMode ? "Adds, crosses out or removes this note in the selected cells." : "Places this digit in the selected cell.")
        .accessibilityShowsLargeContentViewer()
    }
}

/// A paper key with a solid lip underneath (no drop shadow on the text).
struct KeyStyle: ButtonStyle {
    let face: Color
    let done: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let drop: CGFloat = 3
        let sink: CGFloat = pressed ? 2 : 0
        let shape = RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous)
        return ZStack {
            shape.fill(Palette.keyLip).offset(y: drop)
            shape.fill(face).offset(y: sink)
            configuration.label.offset(y: sink)
        }
        .padding(.bottom, drop)
        // A finished digit fades as one piece, so its number stays readable on its key.
        .compositingGroup()
        .opacity(done ? 0.6 : 1)
        .animation(Motion.press, value: pressed)
        .contentShape(Rectangle().inset(by: -2.5))
    }
}

struct HintCard: View {
    @EnvironmentObject var store: GameStore
    let hint: HintInfo
    let minHeight: CGFloat
    /// Short screens: slimmer padding so one more line of text fits.
    var tight = false
    /// The line that explains the outlines. It is the first thing to go when room is short.
    var helper = true
    /// The fallback when the text is taller than the room available: the text scrolls, the buttons stay.
    var scrolls = false
    @AccessibilityFocusState var focused: Bool

    private var closeTitle: String { hint.kind == .place ? "Got it" : "Keep trying" }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Palette.hint).frame(width: 4)
            VStack(alignment: .leading, spacing: tight ? 6 : 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Palette.hint)
                    Text(hint.title).font(Typo.headline).foregroundStyle(Palette.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focused)
                if scrolls {
                    ScrollView { explanation }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.visible)
                        .scrollIndicatorsFlash(onAppear: true)
                } else {
                    explanation
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Button(action: { store.closeHintCard() }) {
                        Text(closeTitle).font(Typo.headline).foregroundStyle(Palette.ink2)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .contentShape(Rectangle())
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
            .padding(tight ? 10 : 12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: scrolls ? nil : minHeight, maxHeight: scrolls ? .infinity : nil, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: !scrolls)
        .background(Palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onAppear { focused = true }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hint.body).font(Typo.callout).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if helper && hint.kind == .place {
                Text(hint.keyCells.subtracting([hint.cell]).isEmpty
                     ? "The outlined cell is the one you can fill."
                     : "Dashed marks the pattern. Solid is the cell to fill.")
                    .font(Typo.footnote).foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
