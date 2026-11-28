import Foundation

enum Tier: String, Codable, CaseIterable, Identifiable {
    case hard, expert, nightmare
    var id: String { rawValue }
    var name: String {
        switch self { case .hard: "Hard"; case .expert: "Expert"; case .nightmare: "Nightmare" }
    }
    var range: String {
        switch self { case .hard: "4.0–4.4"; case .expert: "4.5–4.9"; case .nightmare: "5.0+" }
    }
    /// Number of coral cells in the tier glyph.
    var level: Int {
        switch self { case .hard: 1; case .expert: 2; case .nightmare: 3 }
    }
    var blurb: String {
        switch self {
        case .hard: "X-Wings, XY-Wings, W-Wings, unique rectangles."
        case .expert: "Swordfish, jellyfish and single-digit chains."
        case .nightmare: "XY-chains and puzzles that go beyond them."
        }
    }
}

struct PuzzleEntry {
    let puzzle: String
    let rating: Double
    let tech: String
}

struct UndoEntry: Codable {
    var notes: [Int]
    var cross: [Int]
}

struct GameState: Codable {
    var index: Int
    var puzzle: String
    var rating: Double
    var tech: String
    var vals: [Int]
    var notes: [Int]
    var cross: [Int]
    var elapsed: Double = 0
    var mistakes = 0
    var hints = 0
    var combo = 1
    var lastAt: Double = -1
    var points = 0
    var penalties = 0
    var reveals = 0
    var undo: [UndoEntry] = []

    func isGiven(_ i: Int) -> Bool {
        let u = puzzle.utf8
        return u[u.index(u.startIndex, offsetBy: i)] != 48
    }
}

extension GameState {
    enum CodingKeys: String, CodingKey { case index, puzzle, rating, tech, vals, notes, cross, elapsed, mistakes, hints, combo, lastAt, points, penalties, reveals, undo }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let blank = [Int](repeating: 0, count: 81)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? -1
        puzzle = try c.decode(String.self, forKey: .puzzle)
        rating = try c.decode(Double.self, forKey: .rating)
        tech = try c.decodeIfPresent(String.self, forKey: .tech) ?? ""
        vals = try c.decodeIfPresent([Int].self, forKey: .vals) ?? Sudoku.parse(puzzle)
        notes = try c.decodeIfPresent([Int].self, forKey: .notes) ?? blank
        cross = try c.decodeIfPresent([Int].self, forKey: .cross) ?? blank
        elapsed = try c.decodeIfPresent(Double.self, forKey: .elapsed) ?? 0
        mistakes = try c.decodeIfPresent(Int.self, forKey: .mistakes) ?? 0
        hints = try c.decodeIfPresent(Int.self, forKey: .hints) ?? 0
        combo = try c.decodeIfPresent(Int.self, forKey: .combo) ?? 1
        lastAt = try c.decodeIfPresent(Double.self, forKey: .lastAt) ?? -1
        points = try c.decodeIfPresent(Int.self, forKey: .points) ?? 0
        penalties = try c.decodeIfPresent(Int.self, forKey: .penalties) ?? 0
        reveals = try c.decodeIfPresent(Int.self, forKey: .reveals) ?? 0
        undo = (try? c.decodeIfPresent([UndoEntry].self, forKey: .undo)) ?? []
    }
    /// Shape and consistency check for a decoded game.
    var isWellFormed: Bool {
        guard puzzle.utf8.count == 81, vals.count == 81, notes.count == 81, cross.count == 81,
              vals.allSatisfy({ (0...9).contains($0) }),
              let sol = Sudoku.solve(Sudoku.parse(puzzle)).solution else { return false }
        return (0..<81).allSatisfy { vals[$0] == 0 || vals[$0] == sol[$0] }
    }
}

struct RunState: Codable {
    var tier: Tier
    var score = 0
    var hearts = Rules.hearts
    var solved = 0
    var bestCombo = 1
    var game: GameState
}

extension RunState {
    /// Nothing has happened in this run yet, so replacing it loses nothing.
    var untouched: Bool {
        solved == 0 && score == 0 && hearts == Rules.hearts
            && game.points == 0 && game.mistakes == 0 && game.hints == 0 && game.reveals == 0
    }
}

struct Best: Codable {
    var run = 0
    var fastest = 0
    var solved = 0
    var combo = 0
}

struct SaveData: Codable {
    var run: RunState?
    var bests: [String: Best] = [:]
    var played: [String: [Int]] = [:]
    /// A hint the player paid for and has not used yet, with the puzzle it belongs to.
    var hint: HintInfo?
    var hintPuzzle: String?
}

extension SaveData {
    enum CodingKeys: String, CodingKey { case run, bests, played, hint, hintPuzzle }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        run = try? c.decodeIfPresent(RunState.self, forKey: .run)   // a bad run never costs the bests
        bests = (try? c.decodeIfPresent([String: Best].self, forKey: .bests)) ?? [:]
        played = (try? c.decodeIfPresent([String: [Int]].self, forKey: .played)) ?? [:]
        hint = try? c.decodeIfPresent(HintInfo.self, forKey: .hint)
        hintPuzzle = try? c.decodeIfPresent(String.self, forKey: .hintPuzzle)
    }
}

extension Best {
    enum CodingKeys: String, CodingKey { case run, fastest, solved, combo }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        run = try c.decodeIfPresent(Int.self, forKey: .run) ?? 0
        fastest = try c.decodeIfPresent(Int.self, forKey: .fastest) ?? 0
        solved = try c.decodeIfPresent(Int.self, forKey: .solved) ?? 0
        combo = try c.decodeIfPresent(Int.self, forKey: .combo) ?? 0
    }
}

enum Rules {
    static let comboWindow: Double = 20
    static let maxCombo = 5
    static let hearts = 3
    static let mistakeCost = 250
    static let hintCost = 300
    static let revealCost = 500

    static func multiplier(_ rating: Double) -> Double { max(1, rating - 3) }
    /// Par time in seconds: 15 minutes at 4.0, plus 15 minutes per rating point.
    static func par(_ rating: Double) -> Double { ((15 + (rating - 4) * 15) * 60).rounded() }
}

struct HintInfo: Codable {
    enum Kind: String, Codable { case place, stuck }
    var kind: Kind
    var cell: Int
    var digit: Int
    var title: String
    var body: String
    var keyCells: Set<Int>
}

struct SolvedSummary {
    var puzzleNumber: Int
    var previousRunScore: Int
    var rating: Double
    var tech: String
    var elapsed: Double
    var par: Double
    var points: Int
    var timeBonus: Int
    var cleanBonus: Int?
    var mistakes: Int
    var hints: Int
    var reveals: Int
    var penalties: Int
    var heartRestored: Bool
    var hearts: Int
    var runScore: Int
    var fastestPB: Bool
}

struct RunOverSummary {
    var previousBest: Int
    var tier: Tier
    var rating: Double
    var tech: String
    var solved: Int
    var bestCombo: Int
    var score: Int
    var newBest: Bool
    /// False when the player ended the run themselves.
    var outOfHearts = true
}

enum Overlay {
    case solved(SolvedSummary)
    case runOver(RunOverSummary)
    case paused
}

enum GameEvent {
    case select, note
    case placed(cell: Int, digit: Int, points: Int, combo: Int, revealed: Bool)
    case unitComplete
    case digitComplete(Int)
    case mistake(cell: Int, heartsLeft: Int)
    case hint, solved, newBest, runOver, pause
}

/// A wrong digit shown briefly in its cell.
struct WrongEntry: Equatable {
    let cell: Int
    let digit: Int
    let token: Int
}

/// Rows, columns and boxes completed by the last placement.
struct UnitFlash: Equatable {
    let cells: Set<Int>
    let origin: Int
    let token: Int
}

/// All nine of a digit placed.
struct DigitPulse: Equatable {
    let digit: Int
    let token: Int
}

struct ScorePop: Identifiable {
    enum Kind { case points, penalty, hint }
    let id = UUID()
    let cell: Int
    let text: String
    var combo: Int = 1
    var kind: Kind = .points
}

func formatTime(_ seconds: Double) -> String {
    let s = Int(seconds)
    let h = s / 3600, m = (s / 60) % 60, x = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
}

extension RunState {
    enum CodingKeys: String, CodingKey { case tier, score, hearts, solved, bestCombo, game }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tier = try c.decode(Tier.self, forKey: .tier)
        score = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
        hearts = try c.decodeIfPresent(Int.self, forKey: .hearts) ?? Rules.hearts
        solved = try c.decodeIfPresent(Int.self, forKey: .solved) ?? 0
        bestCombo = try c.decodeIfPresent(Int.self, forKey: .bestCombo) ?? 1
        game = try c.decode(GameState.self, forKey: .game)
    }
}

/// Reader-facing name for a bank technique tag.
func techDisplayName(_ tech: String) -> String {
    switch tech {
    case "Beyond": return "Beyond chains"
    case "": return "Hard logic"
    default: return tech
    }
}
