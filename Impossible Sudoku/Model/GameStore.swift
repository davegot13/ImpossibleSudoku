import Foundation
#if canImport(Combine)
import Combine
#endif

enum Screen { case home, game }

/// Game time, published separately so the 4-per-second clock only redraws the timer and combo ring.
final class GameClock: ObservableObject {
    @Published var elapsed: Double = 0
}

/// All game state and rules. Views read from it and call its actions.
final class GameStore: ObservableObject {
    // Persistent
    @Published var run: RunState?
    @Published var bests: [String: Best] = [:]
    private var played: [String: [Int]] = [:]

    // Session UI state
    @Published var screen: Screen = .home
    @Published var selection: Set<Int> = []
    @Published var primary = -1
    @Published var notesMode = false
    @Published var digitHighlight = 0
    @Published var paused = false
    @Published var hint: HintInfo?
    @Published var hintCardOpen = false
    @Published var overlay: Overlay?
    @Published var pops: [ScorePop] = []
    @Published private(set) var bankLoaded = false
    @Published var showSettings = false
    @Published var showHowTo = false
    /// A tier picked before the first "How to play"; the run starts when it closes.
    @Published var pendingTierAfterHowTo: Tier?

    // Feedback state for animations
    @Published var wrongEntry: WrongEntry?
    @Published var unitFlash: UnitFlash?
    @Published var digitPulse: DigitPulse?
    @Published var solveToken = 0
    /// True from the last placement until the summary shows; input and the clock stop meanwhile.
    @Published var celebrating = false
    /// The run as it looked when the puzzle was solved or the run ended, shown behind the summary.
    @Published var frozen: RunState?

    let clock = GameClock()
    var onEvent: ((GameEvent) -> Void)?
    /// Set by the app from scenePhase; the clock only runs while the app is in front.
    var appActive = true { didSet { if appActive && !oldValue { lastTick = Date() } } }
    private var timer: Timer?
    private var lastTick = Date()
    private var token = 0

    private(set) var bank: [Tier: [PuzzleEntry]] = [:]
    private(set) var solution: [Int] = []
    private var dragMode: Bool? = nil   // true adds cells, false removes
    private var dragLast = -1
    private var sinceSave: Double = 0
    private let saveURL: URL

    init(saveURL: URL? = nil, startClock: Bool = true) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.saveURL = saveURL ?? dir.appendingPathComponent("impossible-sudoku-save.json")
        load()
        if startClock {
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.clockFired() }
            RunLoop.main.add(t, forMode: .common)   // keeps ticking while a scroll view is tracking
            timer = t
        }
    }

    private func clockFired() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        if appActive { tick(dt) }
    }

    private func nextToken() -> Int { token += 1; return token }

    // MARK: - Bank and persistence

    func loadBank(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([String].self, from: data) else { return }
        var b: [Tier: [PuzzleEntry]] = [.hard: [], .expert: [], .nightmare: []]
        for line in rows {
            let p = line.split(separator: "|").map(String.init)
            guard p.count == 4, let tier = Tier(rawValue: p[0]), let r = Double(p[2]), p[1].utf8.count == 81 else { continue }
            b[tier]!.append(PuzzleEntry(puzzle: p[1], rating: r / 10, tech: p[3]))
        }
        bank = b
        bankLoaded = true
        // A saved run that no longer makes sense (corrupted file) is dropped.
        if let r = run, !isValid(r.game) { run = nil; save() }
    }

    private func isValid(_ g: GameState) -> Bool {
        g.puzzle.utf8.count == 81 && g.vals.count == 81 && g.notes.count == 81 && g.cross.count == 81
            && Sudoku.solve(Sudoku.parse(g.puzzle)).count == 1
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let s = try? JSONDecoder().decode(SaveData.self, from: data) else { return }
        run = s.run; bests = s.bests; played = s.played
        clock.elapsed = s.run?.game.elapsed ?? 0
    }

    func save() {
        sinceSave = 0
        syncElapsed()
        let s = SaveData(run: run, bests: bests, played: played)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: saveURL, options: .atomic) }
    }

    /// Copies the live clock into the saved game state.
    private func syncElapsed() {
        if let r = run, r.game.elapsed != clock.elapsed { run!.game.elapsed = clock.elapsed }
    }

    func best(_ t: Tier) -> Best { bests[t.rawValue] ?? Best() }
    private func updateBest(_ t: Tier, _ f: (inout Best) -> Void) {
        var b = best(t); f(&b); bests[t.rawValue] = b
    }

    func resetStatistics() {
        bests = [:]
        save()
    }

    // MARK: - Runs

    private func newGame(_ tier: Tier) -> GameState? {
        let list = bank[tier] ?? []
        guard !list.isEmpty else { return nil }
        var used = played[tier.rawValue] ?? []
        if used.count >= list.count { used = [] }
        let usedSet = Set(used)
        let open = (0..<list.count).filter { !usedSet.contains($0) }
        let i = open.randomElement() ?? 0
        used.append(i)
        played[tier.rawValue] = used
        let e = list[i]
        return GameState(index: i, puzzle: e.puzzle, rating: e.rating, tech: e.tech,
                         vals: Sudoku.parse(e.puzzle), notes: Array(repeating: 0, count: 81), cross: Array(repeating: 0, count: 81))
    }

    private var lastStart = Date.distantPast

    func startRun(_ tier: Tier) {
        guard Date().timeIntervalSince(lastStart) > 0.6 else { return }   // a double tap must not burn two puzzles
        guard bankLoaded, let g = newGame(tier) else { return }
        lastStart = Date()
        if run != nil { _ = finishRun() }
        run = RunState(tier: tier, game: g)
        clock.elapsed = 0
        save()
        enterGame()
    }

    func resumeRun() { if run != nil { enterGame(keepHint: true) } }

    /// Ends the current run, recording its score. Returns whether it set a new best.
    @discardableResult
    func finishRun() -> Bool {
        guard let r = run else { return false }
        var pb = false
        if r.score > 0 && r.score > best(r.tier).run { updateBest(r.tier) { $0.run = r.score }; pb = true }
        run = nil
        save()
        return pb
    }

    private func enterGame(keepHint: Bool = false) {
        guard let r = run else { return }
        let keptHint = keepHint ? hint : nil
        solution = Sudoku.solve(Sudoku.parse(r.game.puzzle)).solution ?? []
        clock.elapsed = r.game.elapsed
        selection = []; primary = -1; notesMode = false; digitHighlight = 0
        paused = false; hint = keptHint; hintCardOpen = false; overlay = nil
        frozen = nil; celebrating = false; wrongEntry = nil; unitFlash = nil; digitPulse = nil; pops = []
        dragMode = nil
        screen = .game
        // A save taken between the last move and its summary (app killed) would otherwise leave a dead board.
        if r.hearts <= 0 { runOver() }
        else if !r.game.vals.contains(0) { puzzleSolved() }
    }

    func goHome() {
        save()
        hintCardOpen = false; frozen = nil; celebrating = false; pops = []
        screen = .home
    }

    /// The run shown on the game screen: the frozen snapshot during a summary, otherwise the live run.
    var shownRun: RunState? { frozen ?? run }

    // MARK: - Derived state

    var focusDigit: Int {
        guard let g = shownRun?.game else { return 0 }
        if selection.count == 1, primary >= 0, g.vals[primary] != 0 { return g.vals[primary] }
        return digitHighlight
    }

    var comboShown: Int {
        guard frozen == nil, let g = run?.game, g.lastAt >= 0, clock.elapsed - g.lastAt <= Rules.comboWindow else { return 1 }
        return g.combo
    }

    var comboFraction: Double {
        guard frozen == nil, let g = run?.game, g.lastAt >= 0 else { return 0 }
        return max(0, Rules.comboWindow - (clock.elapsed - g.lastAt)) / Rules.comboWindow
    }

    func remaining(_ d: Int) -> Int {
        guard let g = shownRun?.game else { return 0 }
        return 9 - g.vals.filter { $0 == d }.count
    }

    /// The player can act on the board.
    var isInteractive: Bool {
        screen == .game && !paused && overlay == nil && !celebrating && frozen == nil && (run?.hearts ?? 0) > 0
    }

    var isActive: Bool { isInteractive }

    // MARK: - Clock

    func tick(_ dt: Double) {
        guard isActive, dt > 0 else { return }
        let step = min(dt, 1)
        clock.elapsed += step
        sinceSave += step
        if sinceSave > 5 { save() }
    }

    func setPaused(_ p: Bool) {
        guard run != nil, screen == .game else { return }
        if p {
            guard overlay == nil, !celebrating else { return }
            paused = true
            overlay = .paused
            dragMode = nil
            onEvent?(.pause)
        } else {
            paused = false
            if case .paused? = overlay { overlay = nil }
            lastTick = Date()
        }
        save()
    }

    /// Called when the app leaves the foreground mid-game.
    func appWentToBackground() {
        if isInteractive { setPaused(true) } else { save() }
    }

    // MARK: - Selection

    func touchBegan(_ i: Int) {
        guard isInteractive, (0..<81).contains(i), let g = run?.game else { return }
        if notesMode {
            // Notes view: tap toggles a cell in the selection, drag sweeps cells in or out.
            if selection.count == 1, primary >= 0, g.vals[primary] != 0 {
                let same = primary == i
                selection = []; primary = -1
                if same { dragMode = nil; return }
            }
            dragMode = !selection.contains(i)
            dragLast = -1
            dragTo(i)
        } else {
            // Tapping the selected cell keeps it selected, so a quick second tap before a digit never drops the target.
            selection = [i]; primary = i
            if primary >= 0 && g.vals[primary] != 0 { digitHighlight = 0 }
            onEvent?(.select)
        }
    }

    func touchMoved(_ i: Int) {
        guard dragMode != nil, isInteractive else { return }
        dragTo(i)
    }

    func touchEnded() { dragMode = nil; dragLast = -1 }

    private func dragTo(_ i: Int) {
        guard let add = dragMode, i != dragLast, (0..<81).contains(i) else { return }
        dragLast = i
        let before = selection.count
        if add { selection.insert(i); primary = i }
        else { selection.remove(i); primary = selection.sorted().last ?? -1 }
        if selection.count != before { onEvent?(.select) }
    }

    /// One tap on a cell (VoiceOver activation and keyboard).
    func tapCell(_ i: Int) { touchBegan(i); touchEnded() }

    /// Makes `i` part of the selection without toggling it off.
    func select(_ i: Int) {
        guard isInteractive, (0..<81).contains(i) else { return }
        if !selection.contains(i) {
            if notesMode { selection.insert(i) } else { selection = [i] }
        }
        primary = i
    }

    /// VoiceOver digit action on a cell.
    func accessibilityInput(_ d: Int, at i: Int) {
        guard isInteractive, (0..<81).contains(i) else { return }
        selection = [i]; primary = i      // the action was named for this cell only
        input(d)
    }

    func clearSelection() { selection = []; primary = -1 }

    func toggleNotes() {
        notesMode.toggle()
        if !notesMode && selection.count > 1 {
            selection = primary >= 0 ? [primary] : []
        }
    }

    func moveSelection(dr: Int, dc: Int) {
        guard isInteractive else { return }
        let cur = primary >= 0 ? primary : 40
        let r = (Sudoku.row[cur] + dr + 9) % 9, c = (Sudoku.col[cur] + dc + 9) % 9
        primary = r * 9 + c
        selection = [primary]
        if let g = run?.game, g.vals[primary] != 0 { digitHighlight = 0 }
    }

    // MARK: - Input

    func input(_ d: Int) {
        guard (1...9).contains(d), var r = run else { return }
        let b = Sudoku.bit(d)
        let targets = selection.filter { r.game.vals[$0] == 0 }.sorted()
        if targets.isEmpty || !isInteractive {
            // With nothing to fill, a digit key just lights up that digit (allowed any time the board is visible).
            if frozen == nil && !paused {
                digitHighlight = digitHighlight == d ? 0 : d
                if !notesMode && isInteractive { clearSelection() }
            }
            return
        }
        if notesMode {
            // A digit already noted gets crossed out (or restored if every one is crossed); a missing digit gets added.
            pushUndo(&r.game)
            let withNote = targets.filter { r.game.notes[$0] & b != 0 }
            if withNote.isEmpty {
                for i in targets { r.game.notes[i] |= b; r.game.cross[i] &= ~b }
            } else if withNote.allSatisfy({ r.game.cross[$0] & b != 0 }) {
                for i in withNote { r.game.cross[i] &= ~b }
            } else {
                for i in withNote { r.game.cross[i] |= b }
            }
            run = r
            digitHighlight = d
            onEvent?(.note)
            save()
            return
        }
        let cell = targets[0]
        if r.game.vals.filter({ $0 == d }).count == 9 {
            // All nine are placed, so this can only be wrong: light the digit up instead of costing a heart.
            digitHighlight = d
            return
        }
        guard cell < solution.count else { return }
        if d == solution[cell] {
            digitHighlight = d
            placeCorrect(cell, d, scored: true)
        } else {
            mistake(cell, d)
        }
    }

    private func pushUndo(_ g: inout GameState) {
        g.undo.append(UndoEntry(notes: g.notes, cross: g.cross))
        if g.undo.count > 60 { g.undo.removeFirst() }
    }

    private func placeCorrect(_ i: Int, _ d: Int, scored: Bool) {
        guard var r = run, r.game.vals[i] == 0 else { return }
        r.game.vals[i] = d; r.game.notes[i] = 0; r.game.cross[i] = 0
        let nb = ~Sudoku.bit(d)
        for p in Sudoku.peers[i] { r.game.notes[p] &= nb; r.game.cross[p] &= nb }
        // Keep the undo history consistent with the placement, so Undo can't bring back notes it just cleared.
        for k in r.game.undo.indices where r.game.undo[k].notes.count == 81 && r.game.undo[k].cross.count == 81 {
            r.game.undo[k].notes[i] = 0; r.game.undo[k].cross[i] = 0
            for p in Sudoku.peers[i] { r.game.undo[k].notes[p] &= nb; r.game.undo[k].cross[p] &= nb }
        }
        var pts = 0
        if scored {
            let g = r.game, now = clock.elapsed
            r.game.combo = g.lastAt >= 0 && now - g.lastAt <= Rules.comboWindow ? min(Rules.maxCombo, g.combo + 1) : 1
            r.game.lastAt = now
            pts = Int((100 * Rules.multiplier(g.rating) * Double(r.game.combo)).rounded())
            r.score += pts; r.game.points += pts
            if r.game.combo > r.bestCombo { r.bestCombo = r.game.combo }
            let combo = r.game.combo
            if combo > best(r.tier).combo { updateBest(r.tier) { $0.combo = combo } }
            addPop(i, "+\(pts.formatted())", combo: combo, kind: .points)
        }
        run = r
        hint = nil; hintCardOpen = false
        if wrongEntry?.cell == i { wrongEntry = nil }
        onEvent?(.placed(cell: i, digit: d, points: pts, combo: r.game.combo, revealed: !scored))

        // Completed rows, columns and boxes.
        let done = Sudoku.units.filter { $0.contains(i) && $0.allSatisfy { r.game.vals[$0] != 0 } }
        let solvedNow = !r.game.vals.contains(0)
        if !done.isEmpty && !solvedNow {
            unitFlash = UnitFlash(cells: Set(done.flatMap { $0 }), origin: i, token: nextToken())
            onEvent?(.unitComplete)
        }
        if r.game.vals.filter({ $0 == d }).count == 9 && !solvedNow {
            digitPulse = DigitPulse(digit: d, token: nextToken())
            onEvent?(.digitComplete(d))
        }
        save()
        if solvedNow {
            celebrating = true
            selection = []; primary = -1
            solveToken += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { [weak self] in self?.puzzleSolved() }
        }
    }

    private func mistake(_ i: Int, _ d: Int) {
        guard var r = run else { return }
        r.game.mistakes += 1
        r.hearts = max(0, r.hearts - 1)
        let before = r.score
        r.score -= Rules.mistakeCost   // may go negative: early penalties are a debt
        r.game.penalties += before - r.score
        r.game.combo = 1; r.game.lastAt = -1
        run = r
        let w = WrongEntry(cell: i, digit: d, token: nextToken())
        wrongEntry = w
        addPop(i, "−\(Rules.mistakeCost)", kind: .penalty)
        onEvent?(.mistake(cell: i, heartsLeft: r.hearts))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            if self?.wrongEntry == w { self?.wrongEntry = nil }
        }
        save()
        if r.hearts <= 0 {
            celebrating = true   // blocks input while the last heart breaks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.runOver() }
        }
    }

    func erase() {
        guard isInteractive, var r = run else { return }
        let ts = selection.filter { r.game.vals[$0] == 0 && r.game.notes[$0] != 0 }
        if ts.isEmpty { return }
        pushUndo(&r.game)
        for i in ts { r.game.notes[i] = 0; r.game.cross[i] = 0 }
        run = r
        onEvent?(.note)
        save()
    }

    func undo() {
        guard isInteractive, var r = run, let u = r.game.undo.popLast() else { return }
        guard u.notes.count == 81, u.cross.count == 81 else { run = r; return }
        // Notes can't come back for cells that have since been filled.
        r.game.notes = (0..<81).map { r.game.vals[$0] == 0 ? u.notes[$0] : 0 }
        r.game.cross = (0..<81).map { r.game.vals[$0] == 0 ? u.cross[$0] : 0 }
        run = r
        onEvent?(.note)
        save()
    }

    func autoNotes() {
        guard isInteractive, var r = run else { return }
        pushUndo(&r.game)
        let c = Sudoku.basicCandidates(r.game.vals)
        for i in 0..<81 where r.game.vals[i] == 0 { r.game.notes[i] = c[i]; r.game.cross[i] &= c[i] }
        run = r
        onEvent?(.note)
        save()
    }

    // MARK: - Hints

    func requestHint() {
        guard isInteractive, var r = run, r.game.vals.contains(0) else { return }
        if let h = hint {
            if h.kind == .place && !hintCardOpen { revealHint(h.cell) } else { hintCardOpen = true }
            return
        }
        r.game.hints += 1; r.game.combo = 1; r.game.lastAt = -1
        let before = r.score
        r.score -= Rules.hintCost
        r.game.penalties += before - r.score
        run = r
        switch Grader.hint(r.game.vals) {
        case let .place(cell, digit, tech, key):
            let extra = key.tech != tech ? " After that, a \(tech.lowercased()) places a digit in the outlined cell." : ""
            hint = HintInfo(kind: .place, cell: cell, digit: digit, title: key.tech, body: key.desc + extra, keyCells: Set(key.cells))
            addPop(cell, "−\(Rules.hintCost)", kind: .hint)
        case .stuck:
            let c = Sudoku.basicCandidates(r.game.vals)
            var bestCell = -1, bestN = 10
            for i in 0..<81 where r.game.vals[i] == 0 && Sudoku.popcount[c[i]] < bestN { bestN = Sudoku.popcount[c[i]]; bestCell = i }
            guard bestCell >= 0, bestCell < solution.count else { return }
            hint = HintInfo(kind: .stuck, cell: bestCell, digit: solution[bestCell], title: "Beyond the technique list",
                            body: "The next step here needs a forcing chain or similar, which hints don't explain yet. You can reveal the outlined cell, the one with the fewest candidates.",
                            keyCells: [])
            addPop(bestCell, "−\(Rules.hintCost)", kind: .hint)
        }
        hintCardOpen = true
        onEvent?(.hint)
        save()
    }

    func revealHint(_ cell: Int) {
        guard isInteractive, var r = run, (0..<81).contains(cell), r.game.vals[cell] == 0, cell < solution.count else { return }
        let before = r.score
        r.score -= Rules.revealCost
        r.game.penalties += before - r.score
        r.game.reveals += 1
        run = r
        addPop(cell, "−\(Rules.revealCost)", kind: .hint)
        placeCorrect(cell, solution[cell], scored: false)
    }

    /// Closes the card; a technique hint keeps its highlights and the Hint button becomes Reveal.
    func closeHintCard() {
        hintCardOpen = false
    }

    // MARK: - End of puzzle and run

    private func puzzleSolved() {
        syncElapsed()
        guard var r = run, !r.game.vals.contains(0), overlay == nil else { celebrating = false; return }
        let previousRunScore = r.score
        let g = r.game, m = Rules.multiplier(g.rating)
        let timeBonus = max(0, Int(((Rules.par(g.rating) - g.elapsed) / 60 * 100 * m).rounded()))
        let clean = g.mistakes == 0 && g.hints == 0
        let cleanBonus = clean ? Int((1500 * m).rounded()) : 0
        r.score += timeBonus + cleanBonus
        r.solved += 1
        let healed = g.mistakes == 0 && r.hearts < Rules.hearts
        if healed { r.hearts += 1 }
        var fastPB = false
        let b = best(r.tier)
        if g.hints == 0 && (b.fastest == 0 || Int(g.elapsed) < b.fastest) { fastPB = true }
        updateBest(r.tier) {
            $0.solved += 1
            if fastPB { $0.fastest = max(1, Int(g.elapsed)) }
        }
        frozen = r                      // keep the finished board on screen behind the summary
        if let next = newGame(r.tier) {
            r.game = next
            solution = Sudoku.solve(Sudoku.parse(next.puzzle)).solution ?? []
        }
        clock.elapsed = 0
        run = r
        save()
        celebrating = false
        onEvent?(.solved)
        overlay = .solved(SolvedSummary(puzzleNumber: r.solved, previousRunScore: previousRunScore,
                                        rating: g.rating, tech: g.tech, elapsed: g.elapsed, par: Rules.par(g.rating),
                                        points: g.points, timeBonus: timeBonus, cleanBonus: clean ? cleanBonus : nil,
                                        mistakes: g.mistakes, hints: g.hints, reveals: g.reveals, penalties: g.penalties, heartRestored: healed, hearts: r.hearts,
                                        runScore: r.score, fastestPB: fastPB))
    }

    func nextPuzzle() {
        overlay = nil
        enterGame()
    }

    private func runOver() {
        guard let r = run, r.hearts <= 0, overlay == nil else { celebrating = false; return }
        let previousBest = best(r.tier).run
        frozen = r
        let pb = finishRun()
        celebrating = false
        onEvent?(.runOver)
        overlay = .runOver(RunOverSummary(previousBest: previousBest, tier: r.tier, rating: r.game.rating, tech: r.game.tech,
                                          solved: r.solved, bestCombo: r.bestCombo, score: r.score, newBest: pb))
        if pb { DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.onEvent?(.newBest) } }
    }

    func closeOverlayToHome() {
        overlay = nil
        paused = false
        goHome()
    }

    // MARK: - Score pops

    private func addPop(_ cell: Int, _ text: String, combo: Int = 1, kind: ScorePop.Kind) {
        let p = ScorePop(cell: cell, text: text, combo: combo, kind: kind)
        pops.append(p)
        if pops.count > 6 { pops.removeFirst(pops.count - 6) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in
            self?.pops.removeAll { $0.id == p.id }
        }
    }

    // MARK: - Debug helpers

    #if DEBUG
    /// Fills every empty cell but one with its answer, for testing the end of a puzzle.
    func debugFillAllButOne() {
        guard var r = run else { return }
        let empties = (0..<81).filter { r.game.vals[$0] == 0 }
        for i in empties.dropLast() where i < solution.count {
            r.game.vals[i] = solution[i]; r.game.notes[i] = 0; r.game.cross[i] = 0
        }
        run = r
        hint = nil; hintCardOpen = false
        if let last = empties.last { selection = [last]; primary = last }
        setPaused(false)
        save()
    }

    /// Leaves one heart, for testing the end of a run.
    func debugOneHeart() {
        guard var r = run else { return }
        r.hearts = 1
        run = r
        setPaused(false)
        save()
    }
    #endif
}
