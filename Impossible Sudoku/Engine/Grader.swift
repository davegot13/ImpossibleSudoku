import Foundation

/// One logical step: digits it places, candidates it removes, and the cells that form the pattern.
struct Step {
    var tech: String
    var place: [(cell: Int, digit: Int)] = []
    var elim: [(cell: Int, digit: Int)] = []
    var cells: [Int] = []
    var desc: String
}

/// Candidate grid the human-technique solver works on.
final class GraderState {
    var vals: [Int]
    var cand: [Int]

    init(_ grid: [Int]) {
        vals = [Int](repeating: 0, count: 81)
        cand = [Int](repeating: 511, count: 81)
        for i in 0..<81 where grid[i] != 0 { place(i, grid[i]) }
    }

    func place(_ i: Int, _ d: Int) {
        vals[i] = d; cand[i] = 0
        let nb = ~Sudoku.bit(d)
        for p in Sudoku.peers[i] { cand[p] &= nb }
    }

    var solved: Bool { !vals.contains(0) }

    func apply(_ s: Step) {
        for p in s.place where vals[p.cell] == 0 { place(p.cell, p.digit) }
        for e in s.elim { cand[e.cell] &= ~Sudoku.bit(e.digit) }
    }
}

enum HintResult {
    case place(cell: Int, digit: Int, tech: String, key: Step)
    case stuck
}

/// Human-technique grader. Techniques run easiest first; the hardest one a puzzle needs sets its rating.
enum Grader {
    static let weights: [String: Double] = [
        "Hidden Single": 1.0, "Naked Single": 1.2, "Pointing": 1.7, "Claiming": 1.9,
        "Naked Pair": 2.0, "Hidden Pair": 2.3, "Naked Triple": 2.6, "Hidden Triple": 2.8,
        "Naked Quad": 3.2, "Hidden Quad": 3.4,
        "X-Wing": 4.0, "XY-Wing": 4.1, "XYZ-Wing": 4.2, "W-Wing": 4.3, "Unique Rectangle": 4.3,
        "Swordfish": 4.5, "Jellyfish": 4.6, "X-Chain": 4.7, "XY-Chain": 5.0, "Beyond": 5.5,
    ]

    typealias Technique = (GraderState) -> Step?
    static let techniques: [Technique] = [
        hiddenSingle, nakedSingle,
        { lockedCandidates($0, claiming: false) }, { lockedCandidates($0, claiming: true) },
        { nakedSubset($0, 2) }, { hiddenSubset($0, 2) },
        { nakedSubset($0, 3) }, { hiddenSubset($0, 3) },
        { nakedSubset($0, 4) }, { hiddenSubset($0, 4) },
        { fish($0, 2) }, xyWing, xyzWing, wWing, uniqueRectangle,
        { fish($0, 3) }, { fish($0, 4) }, xChain, xyChain,
    ]

    static func nextStep(_ s: GraderState) -> Step? {
        for t in techniques { if let st = t(s) { return st } }
        return nil
    }

    /// Rating and hardest technique for a puzzle (same scale as the puzzle bank).
    static func grade(_ grid: [Int]) -> (rating: Double, hardest: String) {
        let s = GraderState(grid)
        var counts: [String: Int] = [:]
        var hardest = "Hidden Single"
        var guardCount = 0
        while !s.solved && guardCount < 2000 {
            guardCount += 1
            guard let st = nextStep(s) else { hardest = "Beyond"; break }
            counts[st.tech, default: 0] += 1
            if weights[st.tech]! > weights[hardest]! { hardest = st.tech }
            s.apply(st)
        }
        let base = weights[hardest]!
        var advanced = 0
        for (k, v) in counts where weights[k]! >= 4.0 { advanced += v }
        let empties = s.vals.filter { $0 == 0 }.count
        var rating: Double
        if hardest == "Beyond" {
            rating = min(5.9, 5.5 + 0.1 * Double(empties / 12) + 0.05 * Double(advanced))
        } else {
            let cap = base >= 5.0 ? 5.4 : base >= 4.5 ? 4.9 : base >= 4.0 ? 4.4 : base + 0.1
            rating = min(cap, base + 0.05 * Double(max(0, advanced - 1)))
        }
        return ((rating * 10).rounded() / 10, hardest)
    }

    /// Next placement a logical solver would make, and the hardest technique it needed to get there.
    static func hint(_ grid: [Int]) -> HintResult {
        let s = GraderState(grid)
        var key: Step? = nil
        for _ in 0..<500 {
            guard let st = nextStep(s) else { return .stuck }
            if key == nil || weights[st.tech]! > weights[key!.tech]! { key = st }
            if let p = st.place.first { return .place(cell: p.cell, digit: p.digit, tech: st.tech, key: key!) }
            s.apply(st)
        }
        return .stuck
    }

    // MARK: - Helpers

    static func choose<T>(_ arr: [T], _ k: Int) -> [[T]] {
        var out: [[T]] = []
        var acc: [T] = []
        func rec(_ start: Int) {
            if acc.count == k { out.append(acc); return }
            if start > arr.count - (k - acc.count) { return }
            for i in start...(arr.count - (k - acc.count)) {
                acc.append(arr[i]); rec(i + 1); acc.removeLast()
            }
        }
        if arr.count >= k { rec(0) }
        return out
    }

    static let subsetName = [2: "Pair", 3: "Triple", 4: "Quad"]
    static let fishName = [2: "X-Wing", 3: "Swordfish", 4: "Jellyfish"]

    // MARK: - Techniques

    static func hiddenSingle(_ s: GraderState) -> Step? {
        for u in 0..<27 {
            for d in 1...9 {
                let b = Sudoku.bit(d)
                var pos = -1, n = 0
                for i in Sudoku.units[u] where s.cand[i] & b != 0 { n += 1; pos = i; if n > 1 { break } }
                if n == 1 {
                    return Step(tech: "Hidden Single", place: [(pos, d)], cells: [pos],
                                desc: "In \(Sudoku.unitName(u)), \(d) can only go in \(Sudoku.cellName(pos)).")
                }
            }
        }
        return nil
    }

    static func nakedSingle(_ s: GraderState) -> Step? {
        for i in 0..<81 where s.vals[i] == 0 && Sudoku.popcount[s.cand[i]] == 1 {
            let d = Sudoku.digitsOf[s.cand[i]][0]
            return Step(tech: "Naked Single", place: [(i, d)], cells: [i],
                        desc: "\(Sudoku.cellName(i)) has only one candidate left: \(d).")
        }
        return nil
    }

    static func lockedCandidates(_ s: GraderState, claiming: Bool) -> Step? {
        let range = claiming ? 0..<18 : 18..<27
        for u in range {
            for d in 1...9 {
                let b = Sudoku.bit(d)
                let cells = Sudoku.units[u].filter { s.cand[$0] & b != 0 }
                if cells.count < 2 { continue }
                var targets: [Int] = []
                if claiming {
                    let bx = Sudoku.box[cells[0]]
                    if !cells.allSatisfy({ Sudoku.box[$0] == bx }) { continue }
                    targets.append(18 + bx)
                } else {
                    let r = Sudoku.row[cells[0]], c = Sudoku.col[cells[0]]
                    if cells.allSatisfy({ Sudoku.row[$0] == r }) { targets.append(r) }
                    if cells.allSatisfy({ Sudoku.col[$0] == c }) { targets.append(9 + c) }
                }
                for t in targets {
                    var elim: [(cell: Int, digit: Int)] = []
                    for j in Sudoku.units[t] where s.cand[j] & b != 0 && !cells.contains(j) { elim.append((j, d)) }
                    if !elim.isEmpty {
                        return Step(tech: claiming ? "Claiming" : "Pointing", elim: elim, cells: cells,
                                    desc: "In \(Sudoku.unitName(u)), every \(d) sits in \(Sudoku.unitName(t)), so \(d) comes out of the rest of \(Sudoku.unitName(t)).")
                    }
                }
            }
        }
        return nil
    }

    static func nakedSubset(_ s: GraderState, _ n: Int) -> Step? {
        for u in 0..<27 {
            let empties = Sudoku.units[u].filter { s.vals[$0] == 0 }
            if empties.count <= n { continue }
            let pool = empties.filter { Sudoku.popcount[s.cand[$0]] >= 2 && Sudoku.popcount[s.cand[$0]] <= n }
            for set in choose(pool, n) {
                var m = 0
                for i in set { m |= s.cand[i] }
                if Sudoku.popcount[m] != n { continue }
                var elim: [(cell: Int, digit: Int)] = []
                for j in empties where !set.contains(j) { for d in Sudoku.digitsOf[s.cand[j] & m] { elim.append((j, d)) } }
                if !elim.isEmpty {
                    let ds = Sudoku.digitsOf[m].map(String.init).joined(separator: "/")
                    return Step(tech: "Naked " + subsetName[n]!, elim: elim, cells: set,
                                desc: "In \(Sudoku.unitName(u)), \(set.map(Sudoku.cellName).joined(separator: ", ")) hold only \(ds), so those digits leave the other cells.")
                }
            }
        }
        return nil
    }

    static func hiddenSubset(_ s: GraderState, _ n: Int) -> Step? {
        for u in 0..<27 {
            let empties = Sudoku.units[u].filter { s.vals[$0] == 0 }
            if empties.count <= n { continue }
            var ds: [Int] = []
            for d in 1...9 {
                let c = empties.filter { s.cand[$0] & Sudoku.bit(d) != 0 }.count
                if c >= 1 && c <= n { ds.append(d) }
            }
            for set in choose(ds, n) {
                var m = 0
                for d in set { m |= Sudoku.bit(d) }
                let cells = empties.filter { s.cand[$0] & m != 0 }
                if cells.count != n { continue }
                var elim: [(cell: Int, digit: Int)] = []
                for j in cells { for d in Sudoku.digitsOf[s.cand[j] & ~m & 511] { elim.append((j, d)) } }
                if !elim.isEmpty {
                    return Step(tech: "Hidden " + subsetName[n]!, elim: elim, cells: cells,
                                desc: "In \(Sudoku.unitName(u)), \(set.map(String.init).joined(separator: "/")) only fit in \(cells.map(Sudoku.cellName).joined(separator: ", ")), so other candidates leave those cells.")
                }
            }
        }
        return nil
    }

    static func fish(_ s: GraderState, _ n: Int) -> Step? {
        for d in 1...9 {
            let b = Sudoku.bit(d)
            for byRow in [true, false] {
                var lines: [Int] = []
                var masks = [Int](repeating: 0, count: 9)
                for k in 0..<9 {
                    var m = 0
                    for x in 0..<9 {
                        let i = byRow ? k * 9 + x : x * 9 + k
                        if s.cand[i] & b != 0 { m |= 1 << x }
                    }
                    if Sudoku.popcount[m] >= 2 && Sudoku.popcount[m] <= n { lines.append(k); masks[k] = m }
                }
                for set in choose(lines, n) {
                    var m = 0
                    for k in set { m |= masks[k] }
                    if Sudoku.popcount[m] != n { continue }
                    var elim: [(cell: Int, digit: Int)] = []
                    var cells: [Int] = []
                    for x in 0..<9 where m & (1 << x) != 0 {
                        for k in 0..<9 {
                            let i = byRow ? k * 9 + x : x * 9 + k
                            if s.cand[i] & b == 0 { continue }
                            if set.contains(k) { cells.append(i) } else { elim.append((i, d)) }
                        }
                    }
                    if !elim.isEmpty {
                        let lineWord = byRow ? "rows" : "columns", crossWord = byRow ? "columns" : "rows"
                        return Step(tech: fishName[n]!, elim: elim, cells: cells,
                                    desc: "The \(d)s in \(lineWord) \(set.map { String($0 + 1) }.joined(separator: ", ")) are confined to \(n) \(crossWord), so \(d) leaves the rest of those \(crossWord).")
                    }
                }
            }
        }
        return nil
    }

    static func xyWing(_ s: GraderState) -> Step? {
        for p in 0..<81 where Sudoku.popcount[s.cand[p]] == 2 {
            let pm = s.cand[p]
            let wings = Sudoku.peers[p].filter { Sudoku.popcount[s.cand[$0]] == 2 && Sudoku.popcount[s.cand[$0] & pm] == 1 }
            if wings.count < 2 { continue }
            for a in 0..<wings.count {
                for c in (a + 1)..<wings.count {
                    let A = wings[a], B = wings[c]
                    let ma = s.cand[A], mb = s.cand[B]
                    if ma & pm == mb & pm { continue }
                    let z = ma & mb & ~pm & 511
                    if Sudoku.popcount[z] != 1 || (ma | mb | pm) != (pm | z) { continue }
                    let d = Sudoku.digitsOf[z][0]
                    var elim: [(cell: Int, digit: Int)] = []
                    for j in 0..<81 where j != p && j != A && j != B && s.cand[j] & z != 0 && Sudoku.isPeer[A][j] && Sudoku.isPeer[B][j] { elim.append((j, d)) }
                    if !elim.isEmpty {
                        return Step(tech: "XY-Wing", elim: elim, cells: [p, A, B],
                                    desc: "Pivot \(Sudoku.cellName(p)) with wings \(Sudoku.cellName(A)) and \(Sudoku.cellName(B)): one wing must be \(d), so cells seeing both wings lose \(d).")
                    }
                }
            }
        }
        return nil
    }

    static func xyzWing(_ s: GraderState) -> Step? {
        for p in 0..<81 where Sudoku.popcount[s.cand[p]] == 3 {
            let pm = s.cand[p]
            let wings = Sudoku.peers[p].filter { Sudoku.popcount[s.cand[$0]] == 2 && (s.cand[$0] & ~pm & 511) == 0 }
            if wings.count < 2 { continue }
            for a in 0..<wings.count {
                for c in (a + 1)..<wings.count {
                    let A = wings[a], B = wings[c]
                    if s.cand[A] == s.cand[B] || (s.cand[A] | s.cand[B]) != pm { continue }
                    let z = s.cand[A] & s.cand[B]
                    let d = Sudoku.digitsOf[z][0]
                    var elim: [(cell: Int, digit: Int)] = []
                    for j in 0..<81 where j != p && j != A && j != B && s.cand[j] & z != 0 && Sudoku.isPeer[p][j] && Sudoku.isPeer[A][j] && Sudoku.isPeer[B][j] { elim.append((j, d)) }
                    if !elim.isEmpty {
                        return Step(tech: "XYZ-Wing", elim: elim, cells: [p, A, B],
                                    desc: "Pivot \(Sudoku.cellName(p)) with wings \(Sudoku.cellName(A)) and \(Sudoku.cellName(B)): one of the three is \(d), so cells seeing all three lose \(d).")
                    }
                }
            }
        }
        return nil
    }

    static func wWing(_ s: GraderState) -> Step? {
        let biv = (0..<81).filter { Sudoku.popcount[s.cand[$0]] == 2 }
        if biv.count < 2 { return nil }
        for a in 0..<biv.count {
            for c in (a + 1)..<biv.count {
                let A = biv[a], B = biv[c]
                if s.cand[A] != s.cand[B] || Sudoku.isPeer[A][B] { continue }
                for x in Sudoku.digitsOf[s.cand[A]] {
                    let y = Sudoku.digitsOf[s.cand[A] & ~Sudoku.bit(x)][0]
                    let xb = Sudoku.bit(x), yb = Sudoku.bit(y)
                    for u in 0..<27 {
                        let cs = Sudoku.units[u].filter { s.cand[$0] & xb != 0 }
                        if cs.count != 2 || cs.contains(A) || cs.contains(B) { continue }
                        let P = cs[0], Q = cs[1]
                        let linked = (Sudoku.isPeer[P][A] && Sudoku.isPeer[Q][B]) || (Sudoku.isPeer[P][B] && Sudoku.isPeer[Q][A])
                        if !linked { continue }
                        var elim: [(cell: Int, digit: Int)] = []
                        for j in 0..<81 where j != A && j != B && s.cand[j] & yb != 0 && Sudoku.isPeer[A][j] && Sudoku.isPeer[B][j] { elim.append((j, y)) }
                        if !elim.isEmpty {
                            return Step(tech: "W-Wing", elim: elim, cells: [A, B, P, Q],
                                        desc: "\(Sudoku.cellName(A)) and \(Sudoku.cellName(B)) are both \(x)/\(y) and are linked by the strong \(x) link in \(Sudoku.unitName(u)), so one of them is \(y). Cells seeing both lose \(y).")
                        }
                    }
                }
            }
        }
        return nil
    }

    static func uniqueRectangle(_ s: GraderState) -> Step? {
        for r1 in 0..<9 {
            for r2 in (r1 + 1)..<9 {
                for c1 in 0..<9 {
                    for c2 in (c1 + 1)..<9 {
                        let cs = [r1 * 9 + c1, r1 * 9 + c2, r2 * 9 + c1, r2 * 9 + c2]
                        if Set(cs.map { Sudoku.box[$0] }).count != 2 { continue }
                        if cs.contains(where: { s.vals[$0] != 0 }) { continue }
                        let bivs = cs.filter { Sudoku.popcount[s.cand[$0]] == 2 }
                        if bivs.count != 3 { continue }
                        let m = s.cand[bivs[0]]
                        if !bivs.allSatisfy({ s.cand[$0] == m }) { continue }
                        guard let F = cs.first(where: { !bivs.contains($0) }) else { continue }
                        if s.cand[F] & m != m { continue }
                        let ds = Sudoku.digitsOf[m]
                        return Step(tech: "Unique Rectangle", elim: ds.map { (F, $0) }, cells: cs,
                                    desc: "Three corners of the rectangle are \(ds.map(String.init).joined(separator: "/")). If \(Sudoku.cellName(F)) were either digit the puzzle would have two solutions, so it loses both.")
                    }
                }
            }
        }
        return nil
    }

    /// Single-digit alternating chains (covers coloring, skyscraper, kite).
    static func xChain(_ s: GraderState) -> Step? {
        var best: (depth: Int, step: Step)? = nil
        for d in 1...9 {
            let b = Sudoku.bit(d)
            let cells = (0..<81).filter { s.cand[$0] & b != 0 }
            var strong = [Int: [Int]]()
            for i in cells { strong[i] = [] }
            for u in 0..<27 {
                let cs = Sudoku.units[u].filter { s.cand[$0] & b != 0 }
                if cs.count == 2 { strong[cs[0]]!.append(cs[1]); strong[cs[1]]!.append(cs[0]) }
            }
            for A in cells {
                guard let startLinks = strong[A], !startLinks.isEmpty else { continue }
                var prevT = [Int: Int](), prevF = [Int: Int]()
                var frontier: [Int] = []
                for B in startLinks where prevT[B] == nil { prevT[B] = A; frontier.append(B) }
                var depth = 1
                while !frontier.isEmpty && depth <= 8 {
                    for X in frontier where X != A {
                        var elim: [(cell: Int, digit: Int)] = []
                        for j in cells where j != A && j != X && Sudoku.isPeer[A][j] && Sudoku.isPeer[X][j] { elim.append((j, d)) }
                        if !elim.isEmpty && depth > 1 && (best == nil || depth < best!.depth) {
                            var path = [X]
                            var cur = X
                            var t = true
                            while cur != A || path.count == 1 {
                                cur = (t ? prevT[cur] : prevF[cur]) ?? A
                                path.append(cur); t.toggle()
                                if path.count > 40 { break }
                            }
                            best = (depth, Step(tech: "X-Chain", elim: elim, cells: path.reversed(),
                                                desc: "A chain of strong links on \(d) from \(Sudoku.cellName(A)) to \(Sudoku.cellName(X)) means one of them is \(d), so cells seeing both lose \(d)."))
                        }
                    }
                    if let bd = best?.depth, bd <= depth { break }
                    var next: [Int] = []
                    for X in frontier {
                        for C in cells where C != X && Sudoku.isPeer[X][C] && prevF[C] == nil && C != A {
                            prevF[C] = X
                            for D in strong[C] ?? [] where prevT[D] == nil && D != A { prevT[D] = C; next.append(D) }
                        }
                    }
                    frontier = next
                    depth += 1
                }
            }
        }
        return best?.step
    }

    static func xyChain(_ s: GraderState) -> Step? {
        var best: (len: Int, step: Step)? = nil
        let biv = (0..<81).filter { Sudoku.popcount[s.cand[$0]] == 2 }
        for A in biv {
            for z in Sudoku.digitsOf[s.cand[A]] {
                let zb = Sudoku.bit(z)
                let startOther = Sudoku.digitsOf[s.cand[A] & ~zb][0]
                var prev = [Int: Int]()
                prev[A * 10 + startOther] = -1
                var frontier: [(Int, Int)] = [(A, startOther)]
                var len = 1
                while !frontier.isEmpty && len < 10 {
                    var next: [(Int, Int)] = []
                    for (c, y) in frontier {
                        for B in biv where B != c && Sudoku.isPeer[c][B] && s.cand[B] & Sudoku.bit(y) != 0 {
                            let y2 = Sudoku.digitsOf[s.cand[B] & ~Sudoku.bit(y)][0]
                            let k = B * 10 + y2
                            if prev[k] != nil { continue }
                            prev[k] = c * 10 + y
                            if y2 == z && B != A {
                                var elim: [(cell: Int, digit: Int)] = []
                                for j in 0..<81 where j != A && j != B && s.cand[j] & zb != 0 && Sudoku.isPeer[A][j] && Sudoku.isPeer[B][j] { elim.append((j, z)) }
                                if !elim.isEmpty && (best == nil || len + 1 < best!.len) {
                                    var path: [Int] = []
                                    var kk = k
                                    while kk != -1 { path.append(kk / 10); kk = prev[kk] ?? -1 }
                                    best = (len + 1, Step(tech: "XY-Chain", elim: elim, cells: path.reversed(),
                                                          desc: "A chain of two-candidate cells from \(Sudoku.cellName(A)) to \(Sudoku.cellName(B)) forces one end to be \(z), so cells seeing both ends lose \(z)."))
                                }
                            }
                            next.append((B, y2))
                        }
                    }
                    if best != nil { break }
                    frontier = next
                    len += 1
                }
            }
        }
        return best?.step
    }
}
