import SwiftUI

/// Five short cards, each with a small live demo drawn with the real board cells.
struct HowToPlayView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) var dismiss
    @AppStorage(SettingsKey.seenHowTo) var seenHowTo = false
    @State var page = 0

    private let pages: [(title: String, body: String)] = [
        ("Every digit scores", "Place the right digit to score. Place the next one within 20 seconds to grow your combo, up to ×5."),
        ("Notes for many cells", "Turn on Notes, then tap or drag across cells. A digit you press goes into all of them."),
        ("Cross out", "In Notes, press a digit that's already noted to strike it. Press it again to bring it back."),
        ("Spot a digit", "Press a number with nothing selected, or tap a placed digit. Every copy lights up, and so does every cell that could hold it."),
        ("Scoring", ""),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(Typo.headline)
                    .foregroundStyle(Palette.onGround2)
                    .frame(minWidth: 44, minHeight: 44)
                    .opacity(page < pages.count - 1 ? 1 : 0)
                    .disabled(page >= pages.count - 1)
                    .accessibilityHidden(page >= pages.count - 1)
            }
            .padding(.horizontal, 16)

            TabView(selection: $page) {
                ForEach(0..<pages.count, id: \.self) { k in
                    GeometryReader { pageGeo in
                    ScrollView {
                        pageContent(k, wide: k < 4 && pageGeo.size.width > pageGeo.size.height * 1.25 && pageGeo.size.width >= 600,
                                    big: pageGeo.size.width >= 700 && pageGeo.size.height >= 800)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity, minHeight: pageGeo.size.height - 40)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    }
                    .tag(k)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            PrimaryButton(title: page < pages.count - 1 ? "Next" : "Let's play") {
                if page < pages.count - 1 { withAnimation(Motion.settle) { page += 1 } } else { finish() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 520)
        }
        .background(Palette.groundGradient.ignoresSafeArea())
    }

    /// One tutorial page. Wide, short screens (iPhone Duo inner display in landscape)
    /// put the demo board beside the text instead of above it.
    @ViewBuilder
    private func pageContent(_ k: Int, wide: Bool, big: Bool) -> some View {
        if wide {
            HStack(spacing: 40) {
                DemoBoard(kind: k).frame(width: 230, height: 230)
                VStack(alignment: .leading, spacing: 14) {
                    Text(pages[k].title).font(Typo.title).foregroundStyle(Palette.onGround)
                        .accessibilityAddTraits(.isHeader)
                    Text(pages[k].body).font(Typo.body).foregroundStyle(Palette.onGround2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 360, alignment: .leading)
            }
            .frame(maxWidth: 680)
        } else {
            VStack(spacing: 20) {
                if k < 4 {
                    DemoBoard(kind: k)
                        .scaleEffect(big ? 1.4 : 1)
                        .frame(height: big ? 322 : 230)
                }
                Text(pages[k].title).font(Typo.title).foregroundStyle(Palette.onGround)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if k < 4 {
                    Text(pages[k].body).font(Typo.body).foregroundStyle(Palette.onGround2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScoringList()
                }
            }
            .frame(maxWidth: 520)
        }
    }

    private func finish() {
        seenHowTo = true
        dismiss()
        if let t = store.pendingTierAfterHowTo {
            store.pendingTierAfterHowTo = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation(Motion.settle) { store.startRun(t) } }
        }
    }
}

private struct ScoringList: View {
    private let rules: [(String, String)] = [
        ("star.fill", "Each correct digit scores 100 × (rating − 3) × your combo."),
        ("timer", "The next correct digit within 20 seconds grows the combo, up to ×5."),
        ("heart.fill", "A wrong digit costs a heart and 250 points. Lose all 3 and the run ends."),
        ("sparkles", "No mistakes and no hints earns a clean bonus and gives back a heart."),
        ("stopwatch.fill", "Finish under par for a time bonus. Par starts at 15 minutes for a 4.0."),
        ("lightbulb.fill", "A hint names the technique for 300 points. Revealing the digit costs 500 more."),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rules, id: \.1) { r in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: r.0).foregroundStyle(Palette.gold).frame(width: 24)
                    Text(r.1).font(Typo.body).foregroundStyle(Palette.onGround2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
    }
}

/// A 3x3 board of real cells that loops through a short demo.
private struct DemoBoard: View {
    let kind: Int
    @State var step = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let cell: CGFloat = 64

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.paper)
                Path { p in
                    for k in 1...2 {
                        p.move(to: CGPoint(x: CGFloat(k) * cell, y: 0)); p.addLine(to: CGPoint(x: CGFloat(k) * cell, y: 3 * cell))
                        p.move(to: CGPoint(x: 0, y: CGFloat(k) * cell)); p.addLine(to: CGPoint(x: 3 * cell, y: CGFloat(k) * cell))
                    }
                }
                .stroke(Palette.gridLine, lineWidth: 1)
                ForEach(0..<9, id: \.self) { i in
                    demoCell(i)
                        .frame(width: cell, height: cell)
                        .position(x: (CGFloat(i % 3) + 0.5) * cell, y: (CGFloat(i / 3) + 0.5) * cell)
                }
            }
            .frame(width: 3 * cell, height: 3 * cell)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            if kind == 0 {
                ComboRing(combo: step >= 2 ? 2 : 1, fraction: step >= 1 ? (step >= 2 ? 0.95 : 0.7) : 0, diameter: 44)
            }
        }
        .accessibilityHidden(true)
        .task {
            if reduceMotion { step = 2; return }
            while !Task.isCancelled {
                for s in 0...3 {
                    withAnimation(Motion.pop) { step = s }
                    try? await Task.sleep(for: .milliseconds(900))
                }
            }
        }
    }

    // Demo states per card.
    @ViewBuilder private func demoCell(_ i: Int) -> some View {
        switch kind {
        case 0:
            let vals = [5, 0, 0, 0, 7, 0, 0, 0, 3]
            let placed = (step >= 1 && i == 1 ? 9 : 0) + (step >= 2 && i == 5 ? 2 : 0)
            CellView(size: cell, value: vals[i] != 0 ? vals[i] : placed, given: vals[i] != 0,
                     notes: 0, cross: 0, focusDigit: 0, focus: .none,
                     selected: (step == 0 && i == 1) || (step == 1 && i == 5), hintKey: false, hintTarget: false,
                     wrongDigit: nil, wrongToken: 0, hidden: false, waveToken: 0, waveDelay: 0,
                     pulseActive: false, pulseToken: 0, pulseDelay: 0)
        case 1:
            let sel: Set<Int> = step == 0 ? [] : step == 1 ? [0, 1] : [0, 1, 2]
            let noted = step >= 3 && [0, 1, 2].contains(i)
            CellView(size: cell, value: i == 4 ? 6 : 0, given: true,
                     notes: noted ? Sudoku.bit(4) | Sudoku.bit(8) : Sudoku.bit(8), cross: 0, focusDigit: 0, focus: .none,
                     selected: sel.contains(i) || (step >= 3 && [0, 1, 2].contains(i)), hintKey: false, hintTarget: false,
                     wrongDigit: nil, wrongToken: 0, hidden: false, waveToken: 0, waveDelay: 0,
                     pulseActive: false, pulseToken: 0, pulseDelay: 0)
        case 2:
            let crossed = step == 1 || step == 2
            let notes = Sudoku.bit(2) | Sudoku.bit(5) | Sudoku.bit(7)
            CellView(size: cell, value: [0, 4, 8].contains(i) ? [3, 0, 0, 0, 1, 0, 0, 0, 9][i] : 0, given: true,
                     notes: [0, 4, 8].contains(i) ? 0 : notes, cross: crossed && [1, 2, 5].contains(i) ? Sudoku.bit(2) : 0,
                     focusDigit: 0, focus: .none,
                     selected: [1, 2, 5].contains(i) && step < 3, hintKey: false, hintTarget: false,
                     wrongDigit: nil, wrongToken: 0, hidden: false, waveToken: 0, waveDelay: 0,
                     pulseActive: false, pulseToken: 0, pulseDelay: 0)
        default:
            let vals = [0, 0, 0, 0, 7, 0, 0, 0, 5]
            let b = Sudoku.bit
            let notes = [b(5) | b(9), b(2) | b(5), b(3), b(3) | b(5), 0, b(2) | b(9), b(1) | b(5), b(2) | b(3), 0]
            let cross = i == 6 ? b(5) : 0
            let on = step >= 1
            let f: CellFocus = !on ? .none
                : vals[i] == 5 ? .placed
                : (vals[i] == 0 && notes[i] & b(5) != 0 && cross & b(5) == 0 ? .candidate : .dim)
            CellView(size: cell, value: vals[i], given: true, notes: notes[i], cross: cross,
                     focusDigit: on ? 5 : 0, focus: f,
                     selected: false, hintKey: false, hintTarget: false,
                     wrongDigit: nil, wrongToken: 0, hidden: false, waveToken: 0, waveDelay: 0,
                     pulseActive: false, pulseToken: 0, pulseDelay: 0)
        }
    }
}
