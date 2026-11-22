import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var store: GameStore
    let overlay: Overlay
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.horizontalSizeClass) var hSize
    @AccessibilityFocusState var titleFocused: Bool
    @State var shown = false

    private var scrimOpacity: Double {
        if reduceTransparency { return 0.92 }
        if case .paused = overlay { return 0.78 }
        return 0.55
    }

    var body: some View {
        GeometryReader { geo in
            overlayBody(fold: Fold.region(in: geo), size: geo.size)
        }
    }

    /// On a partly open iPhone Duo the card moves to one half so it never sits across the fold:
    /// the right half like a book, the flat lower half like a laptop.
    private func overlayBody(fold: CGRect?, size: CGSize) -> some View {
        let isPad = hSize == .regular
        let vertical = fold.map { $0.height >= $0.width } ?? false
        // The tallest the card may be: the flat half when partly open like a laptop.
        let maxCardH: CGFloat = {
            guard let f = fold, !vertical else { return .infinity }
            return max(200, size.height - f.maxY - 16)
        }()
        return ZStack(alignment: isPad ? .center : .bottom) {
            Palette.groundDeep.opacity(scrimOpacity)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .onTapGesture { if case .paused = overlay { store.setPaused(false) } }

            CapHeight(maxHeight: maxCardH) {
                ViewThatFits(in: .vertical) {
                    card(isPad)
                    ScrollView { card(isPad) }
                }
            }
            .frame(maxWidth: 440)
            .background {
                if isPad {
                    RoundedRectangle(cornerRadius: Metrics.sheetRadius, style: .continuous).fill(Palette.paper)
                } else {
                    UnevenRoundedRectangle(topLeadingRadius: Metrics.sheetRadius, topTrailingRadius: Metrics.sheetRadius, style: .continuous)
                        .fill(Palette.paper)
                        .ignoresSafeArea(edges: [.bottom, .horizontal])
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 32, y: 16)
            .padding(.horizontal, isPad ? 24 : 0)
            .offset(y: shown ? 0 : 40)
            .opacity(shown ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { escapeAction() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isPad ? .center : .bottom)
            .padding(.leading, vertical ? (fold?.maxX ?? 0) : 0)
            .padding(.top, !vertical ? (fold?.maxY ?? 0) : 0)

            if case .runOver(let r) = overlay, r.newBest {
                ConfettiView().allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .foregroundStyle(Palette.ink)
        .onAppear {
            withAnimation(Motion.sheet) { shown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { titleFocused = true }
        }
    }

    private func card(_ isPad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, isPad ? 24 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func escapeAction() {
        switch overlay {
        case .paused: store.setPaused(false)
        case .solved: store.nextPuzzle()
        case .runOver: store.closeOverlayToHome()
        }
    }

    @ViewBuilder var content: some View {
        switch overlay {
        case .paused: PauseContent(titleFocused: $titleFocused)
        case .solved(let s): SolvedContent(s: s, titleFocused: $titleFocused)
        case .runOver(let r): RunOverContent(r: r, titleFocused: $titleFocused)
        }
    }
}

// MARK: - Shared pieces

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Palette.action, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(ToolPressStyle())
        .keyboardShortcut(.defaultAction)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.headline)
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Badge: View {
    let text: String
    let symbol: String
    let fill: Color
    let ink: Color
    var body: some View {
        Label(text, systemImage: symbol)
            .font(Typo.footnote.weight(.bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill, in: Capsule())
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    var caption: String? = nil
    var valueColor: Color = Palette.ink
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Typo.body)
                if let caption { Text(caption).font(Typo.footnote).foregroundStyle(Palette.ink2) }
            }
            Spacer()
            Text(value).font(Typo.headline).monospacedDigit().foregroundStyle(valueColor)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pause

struct PauseContent: View {
    @EnvironmentObject var store: GameStore
    var titleFocused: AccessibilityFocusState<Bool>.Binding
    @State var confirmEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paused").font(Typo.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocused)
            if let r = store.run {
                Text("\(r.tier.name) · Puzzle \(r.solved + 1) · \(r.score.formatted()) points · \(formatTime(store.clock.elapsed))")
                    .font(Typo.callout).foregroundStyle(Palette.ink2)
                    .padding(.top, 4)
            }
            Text("The clock is stopped and the board is hidden.")
                .font(Typo.footnote).foregroundStyle(Palette.ink2)
                .padding(.top, 2).padding(.bottom, 20)

            PrimaryButton(title: "Resume") { store.setPaused(false) }

            VStack(spacing: 0) {
                MenuRow(title: "How to play", symbol: "questionmark.circle") { store.showHowTo = true }
                Divider()
                MenuRow(title: "Settings", symbol: "gearshape") { store.showSettings = true }
                Divider()
                MenuRow(title: "Home", symbol: "house") { store.closeOverlayToHome() }
                Divider()
                MenuRow(title: "End run", symbol: "flag.checkered", destructive: true) { confirmEnd = true }
            }
            .padding(.top, 12)

            #if DEBUG
            HStack(spacing: 8) {
                Button("Debug: fill all but one") { store.debugFillAllButOne() }
                Button("Debug: 1 heart") { store.debugOneHeart() }
                Button("Debug: theme") {
                    let cur = UserDefaults.standard.integer(forKey: SettingsKey.appearance)
                    UserDefaults.standard.set((cur + 1) % 3, forKey: SettingsKey.appearance)
                }
            }
            .font(Typo.footnote)
            .padding(.top, 10)
            #endif
        }
        .alert("End this run?", isPresented: $confirmEnd) {
            Button("End run", role: .destructive) {
                store.overlay = nil
                store.paused = false
                _ = store.finishRun()
                store.goHome()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your score still counts toward your best.")
        }
    }
}

struct MenuRow: View {
    let title: String
    let symbol: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 24)
                Text(title)
                Spacer()
                if !destructive { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2) }
            }
            .font(Typo.body)
            .foregroundStyle(destructive ? Palette.error : Palette.ink)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Solved

struct SolvedContent: View {
    @EnvironmentObject var store: GameStore
    let s: SolvedSummary
    var titleFocused: AccessibilityFocusState<Bool>.Binding
    @State var revealed = 0
    @State var total: Int
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    init(s: SolvedSummary, titleFocused: AccessibilityFocusState<Bool>.Binding) {
        self.s = s
        self.titleFocused = titleFocused
        _total = State(initialValue: s.previousRunScore)
    }

    private var underPar: Bool { s.elapsed <= s.par }

    /// Why the clean bonus was missed, e.g. "1 mistake · 2 hints".
    private var cleanMissCaption: String {
        var parts: [String] = []
        if s.mistakes > 0 { parts.append(s.mistakes == 1 ? "1 mistake" : "\(s.mistakes) mistakes") }
        if s.hints > 0 { parts.append(s.hints == 1 ? "1 hint" : "\(s.hints) hints") }
        if s.reveals > 0 { parts.append(s.reveals == 1 ? "1 reveal" : "\(s.reveals) reveals") }
        return parts.isEmpty ? "Used a hint" : parts.joined(separator: " · ")
    }

    private var penaltyCaption: String {
        var parts: [String] = []
        if s.mistakes > 0 { parts.append(s.mistakes == 1 ? "1 mistake" : "\(s.mistakes) mistakes") }
        if s.hints > 0 { parts.append(s.hints == 1 ? "1 hint" : "\(s.hints) hints") }
        if s.reveals > 0 { parts.append(s.reveals == 1 ? "1 reveal" : "\(s.reveals) reveals") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Puzzle \(s.puzzleNumber) solved").eyebrowStyle(Palette.badge)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocused)
            Text(formatTime(s.elapsed))
                .font(Typo.scoreHero)
                .padding(.top, 2)
                .accessibilityLabel("Time \(formatTime(s.elapsed))")

            // Elapsed against par.
            HStack(spacing: 10) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.paper2)
                        Capsule().fill(underPar ? Palette.hint : Palette.coral)
                            .frame(width: g.size.width * min(1, s.elapsed / max(1, s.par)))
                    }
                }
                .frame(height: 6)
                Text("par \(formatTime(s.par))").font(Typo.footnote).foregroundStyle(Palette.ink2).monospacedDigit()
            }
            .padding(.top, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(underPar ? "Under par of \(formatTime(s.par))" : "Over par of \(formatTime(s.par))")

            // Technique, rating and earned badges.
            FlowRow {
                Badge(text: techDisplayName(s.tech), symbol: "puzzlepiece.extension.fill", fill: Palette.paper2, ink: Palette.ink)
                Badge(text: String(format: "%.1f", s.rating), symbol: "flame.fill", fill: Palette.gold, ink: Palette.goldInk)
                if s.fastestPB { Badge(text: "Fastest", symbol: "stopwatch.fill", fill: Palette.gold, ink: Palette.goldInk) }
                if s.cleanBonus != nil { Badge(text: "Clean", symbol: "sparkles", fill: Palette.hintFill, ink: Palette.hint) }
                if s.heartRestored { Badge(text: "Heart back", symbol: "heart.fill", fill: Palette.candidate, ink: Palette.badge) }
            }
            .padding(.top, 14)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                row(0) { SummaryRow(label: "Digits and combos", value: s.points.formatted()) }
                row(1) { SummaryRow(label: "Time bonus", value: "+\(s.timeBonus.formatted())") }
                row(2) {
                    if let c = s.cleanBonus {
                        SummaryRow(label: "Clean bonus", value: "+\(c.formatted())")
                    } else {
                        SummaryRow(label: "Clean bonus", value: "—", caption: cleanMissCaption)
                    }
                }
                if s.penalties > 0 {
                    row(3) { SummaryRow(label: "Penalties", value: "−\(s.penalties.formatted())", caption: penaltyCaption, valueColor: Palette.error) }
                }
                Divider().padding(.vertical, 4)
                HStack(alignment: .firstTextBaseline) {
                    Text("Run score").font(Typo.title2)
                    Spacer()
                    Text(total, format: .number)
                        .font(Typo.title2).monospacedDigit()
                        .contentTransition(.numericText(value: Double(total)))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Run score \(s.runScore.formatted())")
            }

            PrimaryButton(title: "Next puzzle") { store.nextPuzzle() }
                .padding(.top, 18)
            SecondaryButton(title: "Home") { store.closeOverlayToHome() }
                .padding(.top, 4)
        }
        .task {
            if reduceMotion { revealed = 5; total = s.runScore; return }
            for k in 1...5 {
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(Motion.count) { revealed = k }
            }
            withAnimation(.easeOut(duration: 0.6)) { total = s.runScore }
        }
    }

    @ViewBuilder private func row<V: View>(_ k: Int, @ViewBuilder _ v: () -> V) -> some View {
        v()
            .opacity(revealed > k ? 1 : 0)
            .offset(y: revealed > k ? 0 : 6)
    }
}

/// Offers its child at most `maxHeight`, so a ViewThatFits inside can fall back to scrolling.
struct CapHeight: Layout {
    var maxHeight: CGFloat
    private func capped(_ p: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: p.width, height: p.height.map { min($0, maxHeight) } ?? (maxHeight.isFinite ? maxHeight : nil))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// Wraps badges onto multiple lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Run over

struct RunOverContent: View {
    @EnvironmentObject var store: GameStore
    let r: RunOverSummary
    var titleFocused: AccessibilityFocusState<Bool>.Binding
    @State var total = 0
    @State var badgeIn = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Run over").eyebrowStyle(Palette.error)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocused)
            Text("\(r.tier.name) · \(r.solved == 1 ? "1 puzzle" : "\(r.solved) puzzles")")
                .font(Typo.footnote).foregroundStyle(Palette.ink2)
                .padding(.top, 2)
            Text(total, format: .number)
                .font(Typo.scoreHero)
                .contentTransition(.numericText(value: Double(total)))
                .padding(.top, 4)
                .accessibilityLabel("Final score \(r.score.formatted())")
            Group {
                if r.newBest {
                    Badge(text: "New best", symbol: "crown.fill", fill: Palette.gold, ink: Palette.goldInk)
                        .scaleEffect(badgeIn ? 1 : 0.6)
                        .opacity(badgeIn ? 1 : 0)
                } else if r.previousBest > 0 {
                    Text("Best \(r.previousBest.formatted())").font(Typo.footnote).foregroundStyle(Palette.ink2)
                }
            }
            .padding(.top, 6)

            HStack(spacing: 8) {
                StatTile(value: "\(r.solved)", label: "Solved")
                StatTile(value: "×\(r.bestCombo)", label: "Best combo")
                StatTile(value: String(format: "%.1f", r.rating), label: "Last rating")
            }
            .padding(.top, 18)

            (Text("Hardest step in the last puzzle: ").foregroundStyle(Palette.ink2)
             + Text(techDisplayName(r.tech)).foregroundStyle(Palette.ink).fontWeight(.semibold))
                .font(Typo.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            PrimaryButton(title: "New run") { store.startRun(r.tier) }
                .padding(.top, 20)
            SecondaryButton(title: "Home") { store.closeOverlayToHome() }
                .padding(.top, 4)
        }
        .task {
            if reduceMotion { total = r.score; badgeIn = true; return }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 1.2)) { total = r.score }
            try? await Task.sleep(for: .milliseconds(1250))
            withAnimation(Motion.pop) { badgeIn = true }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(Typo.headline).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Typo.footnote).foregroundStyle(Palette.ink2).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.horizontal, 6)
        .background(Palette.paper2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Falling paper squares, only for a new best.
struct ConfettiView: View {
    private struct Piece {
        let x: Double, delay: Double, speed: Double, spin: Double, size: Double, drift: Double, color: Color
    }
    private let pieces: [Piece] = (0..<44).map { _ in
        Piece(x: .random(in: 0...1), delay: .random(in: 0...0.5), speed: .random(in: 0.7...1.2),
              spin: .random(in: -4...4), size: .random(in: 6...10), drift: .random(in: -30...30),
              color: [Palette.coral, Palette.gold, Color(hex: 0xFFFDF7), Palette.hint].randomElement()!)
    }
    @State var start = Date()
    @State var done = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        if !reduceMotion && !done {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSince(start)
                Canvas { ctx, size in
                    for p in pieces {
                        let lt = t - p.delay
                        guard lt > 0, lt < 2.4 else { continue }
                        let y = -20 + lt * p.speed * size.height * 0.55
                        let x = p.x * size.width + sin(lt * 3 + p.spin) * p.drift
                        var c = ctx
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(lt * p.spin))
                        c.opacity = max(0, min(1, 2.4 - lt))
                        c.fill(Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size * 0.7), cornerRadius: 2),
                               with: .color(p.color))
                    }
                }
            }
            .ignoresSafeArea()
            .task { try? await Task.sleep(for: .seconds(3)); done = true }
        }
    }
}
