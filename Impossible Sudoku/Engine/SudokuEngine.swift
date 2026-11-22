import Foundation

/// Board geometry, solver and helpers. Cells are indexed 0...80, row-major.
/// Candidate sets are 9-bit masks: bit (d - 1) set means digit d is possible.
enum Sudoku {
    static let row: [Int] = (0..<81).map { $0 / 9 }
    static let col: [Int] = (0..<81).map { $0 % 9 }
    static let box: [Int] = (0..<81).map { ($0 / 27) * 3 + ($0 % 9) / 3 }

    /// 27 units: rows 0-8, columns 9-17, boxes 18-26.
    static let units: [[Int]] = {
        var u: [[Int]] = []
        for r in 0..<9 { u.append((0..<9).map { r * 9 + $0 }) }
        for c in 0..<9 { u.append((0..<9).map { $0 * 9 + c }) }
        for b in 0..<9 {
            let br = (b / 3) * 3, bc = (b % 3) * 3
            var cells: [Int] = []
            for r in 0..<3 { for c in 0..<3 { cells.append((br + r) * 9 + bc + c) } }
            u.append(cells)
        }
        return u
    }()

    static let peers: [[Int]] = (0..<81).map { i in
        var s = Set<Int>()
        for u in [units[row[i]], units[9 + col[i]], units[18 + box[i]]] { for j in u where j != i { s.insert(j) } }
        return s.sorted()
    }

    static let isPeer: [[Bool]] = (0..<81).map { i in
        var r = [Bool](repeating: false, count: 81)
        for j in peers[i] { r[j] = true }
        return r
    }

    static let popcount: [Int] = (0..<512).map { m in (0..<9).reduce(0) { $0 + ((m >> $1) & 1) } }
    static let digitsOf: [[Int]] = (0..<512).map { m in (1...9).filter { m & (1 << ($0 - 1)) != 0 } }

    @inline(__always) static func bit(_ d: Int) -> Int { 1 << (d - 1) }

    static func cellName(_ i: Int) -> String { "r\(row[i] + 1)c\(col[i] + 1)" }
    static func unitName(_ u: Int) -> String {
        u < 9 ? "row \(u + 1)" : u < 18 ? "column \(u - 8)" : "box \(u - 17)"
    }

    static func parse(_ s: String) -> [Int] {
        var g = [Int](repeating: 0, count: 81)
        for (i, ch) in s.utf8.prefix(81).enumerated() where ch >= 49 && ch <= 57 { g[i] = Int(ch) - 48 }
        return g
    }

    /// Backtracking solver with fewest-candidates-first. Stops after `limit` solutions.
    static func solve(_ grid: [Int], limit: Int = 2) -> (count: Int, solution: [Int]?) {
        var g = grid
        var rows = [Int](repeating: 0, count: 9), cols = rows, boxes = rows
        for i in 0..<81 where g[i] != 0 {
            let b = bit(g[i])
            if (rows[row[i]] | cols[col[i]] | boxes[box[i]]) & b != 0 { return (0, nil) }
            rows[row[i]] |= b; cols[col[i]] |= b; boxes[box[i]] |= b
        }
        var count = 0
        var solution: [Int]? = nil
        func rec() {
            var best = -1, bestMask = 0, bestN = 10
            for i in 0..<81 where g[i] == 0 {
                let m = ~(rows[row[i]] | cols[col[i]] | boxes[box[i]]) & 511
                let n = popcount[m]
                if n < bestN { best = i; bestMask = m; bestN = n; if n <= 1 { break } }
            }
            if best == -1 { count += 1; if solution == nil { solution = g }; return }
            if bestN == 0 { return }
            let r = row[best], c = col[best], bx = box[best]
            for d in digitsOf[bestMask] {
                let b = bit(d)
                g[best] = d; rows[r] |= b; cols[c] |= b; boxes[bx] |= b
                rec()
                g[best] = 0; rows[r] &= ~b; cols[c] &= ~b; boxes[bx] &= ~b
                if count >= limit { return }
            }
        }
        rec()
        return (count, solution)
    }

    /// Candidates from placed digits only (what "Auto notes" fills in).
    static func basicCandidates(_ grid: [Int]) -> [Int] {
        (0..<81).map { i in
            if grid[i] != 0 { return 0 }
            var m = 511
            for p in peers[i] where grid[p] != 0 { m &= ~bit(grid[p]) }
            return m
        }
    }
}
