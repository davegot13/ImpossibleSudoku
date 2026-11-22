import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: GameStore
    @AppStorage(SettingsKey.seenHowTo) var seenHowTo = false
    @State var pendingTier: Tier?
    @State var confirmEnd = false
    @State var markIn = false
    @Environment(\.horizontalSizeClass) var hSize

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 760 && geo.size.width > geo.size.height
            let fold = Fold.region(in: geo).flatMap { $0.height >= $0.width ? $0 : nil }
            ScrollView {
                if wide, let fold {
                    // Partly open like a book: one column on each half, nothing across the fold.
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            brandHeader
                            tagline
                            if store.bankLoaded {
                                if let run = store.run {
                                    ResumeCard(run: run, onEnd: { confirmEnd = true }).padding(.top, 24)
                                }
                                howToRow.padding(.top, 24)
                            }
                        }
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 24)
                        .frame(width: fold.minX)
                        Color.clear.frame(width: fold.width)
                        VStack(alignment: .leading, spacing: 0) {
                            if store.bankLoaded { tierList.padding(.top, 20) }
                        }
                        .frame(maxWidth: 460)
                        .padding(.horizontal, 24)
                        .frame(width: max(0, geo.size.width - fold.maxX))
                    }
                    .padding(.bottom, 32)
                    .frame(minHeight: geo.size.height, alignment: .center)
                } else if wide {
                    // Landscape on iPad and the iPhone Duo inner display: brand on the left, tiers on the right.
                    HStack(alignment: .top, spacing: 40) {
                        VStack(alignment: .leading, spacing: 0) {
                            brandHeader
                            tagline
                            if store.bankLoaded {
                                if let run = store.run {
                                    ResumeCard(run: run, onEnd: { confirmEnd = true }).padding(.top, 24)
                                }
                                howToRow.padding(.top, 24)
                            }
                        }
                        .frame(maxWidth: 420)
                        VStack(alignment: .leading, spacing: 0) {
                            if store.bankLoaded {
                                tierList.padding(.top, 20)
                            } else {
                                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(40)
                            }
                        }
                        .frame(maxWidth: 460)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        brandHeader
                        tagline
                        if !store.bankLoaded {
                            ProgressView().tint(.white).frame(maxWidth: .infinity).padding(40)
                        } else {
                            if let run = store.run {
                                ResumeCard(run: run, onEnd: { confirmEnd = true })
                                    .padding(.top, 24)
                            }
                            tierList.padding(.top, 28)
                            howToRow.padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, hSize == .regular ? 32 : 16)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    // Big portrait screens (iPad): sit in the middle instead of leaving the lower half empty.
                    .frame(minHeight: hSize == .regular ? geo.size.height : 0, alignment: .center)
                }
            }
            .scrollIndicators(.hidden)
        }
        .alert("Start a new run?", isPresented: Binding(get: { pendingTier != nil }, set: { if !$0 { pendingTier = nil } }),
               presenting: pendingTier) { t in
            Button("Start new run", role: .destructive) { begin(t) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This ends your current run. Its score still counts toward your best.")
        }
        .alert("End this run?", isPresented: $confirmEnd) {
            Button("End run", role: .destructive) { _ = store.finishRun() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your score still counts toward your best.")
        }
    }

    private var brandHeader: some View {
        HStack(alignment: .top) {
            HStack(alignment: .center, spacing: 14) {
                MarkView(size: 56, coral: [1, 5, 6], animateIn: true)
                VStack(alignment: .leading, spacing: -8) {
                    Text("IMPOSSIBLE").foregroundStyle(Palette.onGround)
                    Text("SUDOKU").foregroundStyle(Palette.coral)
                }
                .font(Typo.wordmark)
                .tracking(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            Button { store.showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.onGround)
                    .frame(width: 44, height: 44)
                    .background(Palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.hairline))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 20)
    }

    private var tagline: some View {
        Text("Only the hardest puzzles. Rated 4.0 and up.")
            .font(Typo.body)
            .foregroundStyle(Palette.onGround2)
            .padding(.top, 14)
    }

    private var tierList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a tier").eyebrowStyle()
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 12) {
                ForEach(Tier.allCases) { tier in
                    Button { tapTier(tier) } label: {
                        TierCard(tier: tier, best: store.best(tier), count: store.bank[tier]?.count ?? 0, locked: Edition.isLocked(tier))
                    }
                    .buttonStyle(CardPressStyle())
                    .hoverEffect(.lift)
                }
            }
        }
    }

    private var howToRow: some View {
        Button { store.showHowTo = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 20))
                Text("How to play").font(Typo.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.onGround3)
            }
            .foregroundStyle(Palette.onGround)
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.hairline))
        }
        .buttonStyle(CardPressStyle())
    }

    private func tapTier(_ t: Tier) {
        if Edition.isLocked(t) { store.showFullApp = true; return }
        if store.run != nil { pendingTier = t } else { begin(t) }
    }

    private func begin(_ t: Tier) {
        store.showFullApp = false
        if !seenHowTo {
            store.pendingTierAfterHowTo = t
            store.showHowTo = true
        } else {
            withAnimation(Motion.settle) { store.startRun(t) }
        }
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// The brand mark: nine paper tiles, some of them coral.
struct MarkView: View {
    let size: CGFloat
    var coral: Set<Int> = [4]
    var animateIn = false
    @State var shown = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        let gap = max(2, size * 0.05)
        let tile = (size - 2 * gap) / 3
        VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { c in
                        let k = r * 3 + c
                        RoundedRectangle(cornerRadius: tile * 0.22, style: .continuous)
                            .fill(coral.contains(k) ? Palette.coral : Palette.markTile)
                            .frame(width: tile, height: tile)
                            .scaleEffect(shown || !animateIn || reduceMotion ? 1 : 0.4)
                            .opacity(shown || !animateIn ? 1 : 0)
                            .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.pop.delay(0.03 * Double(k)), value: shown)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear { shown = true }
    }
}

struct TierCard: View {
    let tier: Tier
    let best: Best
    let count: Int
    var locked = false

    private var stats: [String] {
        var s: [String] = []
        if best.run > 0 { s.append("Best \(best.run.formatted())") }
        if best.fastest > 0 { s.append(formatTime(Double(best.fastest))) }
        if best.solved > 0 { s.append("\(best.solved) solved") }
        if best.combo > 1 { s.append("×\(best.combo)") }
        return s
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            MarkView(size: 40, coral: tierCells)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(tier.name).font(Typo.title2).foregroundStyle(Palette.onGround)
                    Text(tier.range)
                        .font(Typo.footnote.weight(.semibold))
                        .foregroundStyle(Palette.gold)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Palette.gold.opacity(0.16), in: Capsule())
                }
                Text(tier.blurb).font(Typo.callout).foregroundStyle(Palette.onGround2).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.vertical, 4)
                Text(locked ? "\(count.formatted()) puzzles in the full app" : stats.isEmpty ? "\(count.formatted()) puzzles · Not played yet" : stats.joined(separator: " · "))
                    .font(Typo.footnote).monospacedDigit()
                    .foregroundStyle(Palette.onGround2)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: locked ? "lock.fill" : "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.onGround3)
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.hairline))
        .overlay {
            if tier == .nightmare {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.coral.opacity(0.06)).allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier.name), rated \(tier.range)")
        .accessibilityValue(locked ? "In the full app" : stats.isEmpty ? "Not played yet" : stats.joined(separator: ", "))
        .accessibilityHint(locked ? "Shows the full app in the App Store" : "Starts a run")
    }

    private var tierCells: Set<Int> {
        switch tier { case .hard: [4]; case .expert: [2, 6]; case .nightmare: [0, 4, 8] }
    }
}

struct ResumeCard: View {
    @EnvironmentObject var store: GameStore
    let run: RunState
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            MiniBoardView(game: run.game, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text("Continue run").eyebrowStyle(Color.white.opacity(0.85))
                Text("\(run.tier.name) · Puzzle \(run.solved + 1)").font(Typo.headline).foregroundStyle(.white)
                HStack(spacing: 8) {
                    Text(run.score, format: .number).monospacedDigit()
                    HStack(spacing: 2) {
                        ForEach(0..<Rules.hearts, id: \.self) { k in
                            Image(systemName: k < run.hearts ? "heart.fill" : "heart").font(.system(size: 11, weight: .bold))
                        }
                    }
                    Text(formatTime(run.game.elapsed)).monospacedDigit()
                }
                .font(Typo.footnote)
                .foregroundStyle(Color.white.opacity(0.92))
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.action)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
                Menu {
                    Button("End run", systemImage: "flag.checkered", role: .destructive) { onEnd() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 30)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
            }
        }
        .padding(16)
        .background(Palette.action, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius))
        .onTapGesture { withAnimation(Motion.settle) { store.resumeRun() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continue \(run.tier.name) run, puzzle \(run.solved + 1)")
        .accessibilityValue("\(run.score.formatted()) points, \(run.hearts) of \(Rules.hearts) hearts")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.resumeRun() }
        .accessibilityAction(named: "End run") { onEnd() }
    }
}

/// A tiny picture of a board: givens and player digits as small squares.
struct MiniBoardView: View {
    let game: GameState
    let size: CGFloat

    var body: some View {
        let gap: CGFloat = 1.5
        let box = (size - 2 * gap) / 3
        let cell = box / 3
        Canvas { ctx, _ in
            for b in 0..<9 {
                let o = CGPoint(x: CGFloat(b % 3) * (box + gap), y: CGFloat(b / 3) * (box + gap))
                ctx.fill(Path(roundedRect: CGRect(x: o.x, y: o.y, width: box, height: box), cornerRadius: 2), with: .color(Palette.paper))
            }
            for i in 0..<81 where game.vals[i] != 0 {
                let r = i / 9, c = i % 9
                let x = CGFloat(c / 3) * (box + gap) + CGFloat(c % 3) * cell
                let y = CGFloat(r / 3) * (box + gap) + CGFloat(r % 3) * cell
                let inset = cell * 0.2
                let color = game.isGiven(i) ? Palette.ink.opacity(0.55) : Palette.pencil
                ctx.fill(Path(roundedRect: CGRect(x: x + inset, y: y + inset, width: cell - 2 * inset, height: cell - 2 * inset), cornerRadius: 1),
                         with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
