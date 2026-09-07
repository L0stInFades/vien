import CoreGraphics
import Foundation

/// Layered (Sugiyama-style) layout for directed graphs with nested clusters.
///
/// Each cluster is laid out on its own and becomes a compound node of its parent, which keeps the
/// algorithm small and produces the "boxes inside boxes" look people expect from Mermaid subgraphs.
struct GraphLayout {
  struct Result {
    var nodeRects: [String: CGRect] = [:]
    var clusterRects: [String: CGRect] = [:]
    /// Route per edge index (absolute points, source to target, before clipping to shapes).
    var edgeRoutes: [Int: [CGPoint]] = [:]
    var size: CGSize = .zero
  }

  let diagram: GraphDiagram
  let nodeSizes: [String: CGSize]
  let labelSizes: [Int: CGSize]
  var nodeSep: Double = 36
  var rankSep: Double = 44
  var clusterPadding: Double = 16
  var clusterTitleHeight: Double = 22

  init(diagram: GraphDiagram, nodeSizes: [String: CGSize], labelSizes: [Int: CGSize]) {
    self.diagram = diagram
    self.nodeSizes = nodeSizes
    self.labelSizes = labelSizes
  }

  // MARK: - Compound layout

  private struct Local {
    var origin: [String: CGPoint] = [:]  // vertex centre relative to cluster origin
    var size: CGSize = .zero
    var routes: [Int: [CGPoint]] = [:]   // relative points
    var childClusterOrigins: [String: CGPoint] = [:]  // top-left of child cluster rect (relative)
  }

  func run() -> Result {
    var result = Result()
    var clusterSizes: [String: CGSize] = [:]
    var locals: [String: Local] = [:]
    // Post-order over clusters so children are sized before parents.
    func layoutCluster(_ id: String?) -> Local {
      let children = diagram.clusters.filter { $0.parent == id }
      for c in children where locals[c.id] == nil {
        let l = layoutCluster(c.id)
        locals[c.id] = l
        clusterSizes[c.id] = l.size
      }
      return layoutLocal(cluster: id, clusterSizes: clusterSizes)
    }
    let root = layoutCluster(nil)
    result.size = root.size

    // Resolve absolute positions top-down.
    func place(_ id: String?, local: Local, origin: CGPoint) {
      for (vid, centre) in local.origin {
        let abs = CGPoint(x: origin.x + centre.x, y: origin.y + centre.y)
        if let cs = clusterSizes[vid], diagram.clusters.contains(where: { $0.id == vid }) {
          let rect = CGRect(x: abs.x - cs.width / 2, y: abs.y - cs.height / 2, width: cs.width, height: cs.height)
          result.clusterRects[vid] = rect
          let cl = diagram.clusters.first { $0.id == vid }!
          let inner = CGPoint(x: rect.minX + clusterPadding, y: rect.minY + clusterPadding + (cl.title == nil ? 0 : clusterTitleHeight))
          place(vid, local: locals[vid]!, origin: inner)
        } else if let ns = nodeSizes[vid] {
          result.nodeRects[vid] = CGRect(x: abs.x - ns.width / 2, y: abs.y - ns.height / 2, width: ns.width, height: ns.height)
        }
      }
      for (edge, pts) in local.routes {
        result.edgeRoutes[edge] = pts.map { CGPoint(x: origin.x + $0.x, y: origin.y + $0.y) }
      }
    }
    place(nil, local: root, origin: .zero)
    // Re-anchor edge endpoints at the real node centres (they may sit inside child clusters).
    for (i, e) in diagram.edges.enumerated() {
      guard var pts = result.edgeRoutes[i], let a = result.nodeRects[e.from], let b = result.nodeRects[e.to] else { continue }
      pts[0] = CGPoint(x: a.midX, y: a.midY)
      pts[pts.count - 1] = CGPoint(x: b.midX, y: b.midY)
      result.edgeRoutes[i] = pts
    }
    return result
  }

  /// The top-most ancestor of node `id` that is a direct member of `cluster` (a node id or a cluster id).
  private func member(of id: String, in cluster: String?) -> String? {
    guard let node = diagram.node(withID: id) else { return nil }
    var current: String? = node.cluster
    var last: String = id
    while let c = current {
      if c == cluster { return last }
      last = c
      current = diagram.clusters.first { $0.id == c }?.parent
    }
    return cluster == nil ? last : nil
  }

  private func layoutLocal(cluster: String?, clusterSizes: [String: CGSize]) -> Local {
    // Local vertices: direct member nodes + direct child clusters.
    var vertices: [String] = diagram.nodes.filter { $0.cluster == cluster }.map(\.id)
    vertices += diagram.clusters.filter { $0.parent == cluster }.map(\.id)
    var sizes: [String: CGSize] = [:]
    for v in vertices { sizes[v] = nodeSizes[v] ?? clusterSizes[v] ?? CGSize(width: 40, height: 30) }
    // Local edges.
    var localEdges: [(index: Int, from: String, to: String, minLength: Int)] = []
    for (i, e) in diagram.edges.enumerated() {
      guard let a = member(of: e.from, in: cluster), let b = member(of: e.to, in: cluster) else { continue }
      if e.line == .invisible { localEdges.append((i, a, b, e.minLength)); continue }
      localEdges.append((i, a, b, e.minLength))
    }
    let direction = diagram.clusters.first { $0.id == cluster }?.direction ?? diagram.direction
    var local = Local()
    guard !vertices.isEmpty else { return local }
    let layered = Layered(vertices: vertices, sizes: sizes, edges: localEdges, nodeSep: nodeSep, rankSep: rankSep(for: localEdges), horizontal: direction == .LR || direction == .RL)
    let (centres, routes, size) = layered.run()
    // Direction transforms (computed in TB or "LR" canonical form).
    func transform(_ p: CGPoint) -> CGPoint {
      switch direction {
      case .TB, .LR: return p
      case .BT: return CGPoint(x: p.x, y: size.height - p.y)
      case .RL: return CGPoint(x: size.width - p.x, y: p.y)
      }
    }
    for (v, c) in centres { local.origin[v] = transform(c) }
    for (i, pts) in routes { local.routes[i] = pts.map(transform) }
    let title = diagram.clusters.first { $0.id == cluster }?.title
    let pad = cluster == nil ? 0 : clusterPadding
    local.size = CGSize(width: size.width + pad * 2, height: size.height + pad * 2 + (cluster == nil || title == nil ? 0 : clusterTitleHeight))
    return local
  }

  private func rankSep(for edges: [(index: Int, from: String, to: String, minLength: Int)]) -> Double {
    var sep = rankSep
    for e in edges { if let l = labelSizes[e.index] { sep = max(sep, l.height + 28) } }
    return sep
  }
}

/// One level of the layered algorithm: cycle removal, ranking, dummy insertion, ordering, coordinates.
struct Layered {
  let vertices: [String]
  let sizes: [String: CGSize]
  let edges: [(index: Int, from: String, to: String, minLength: Int)]
  let nodeSep: Double
  let rankSep: Double
  /// Layout along x instead of y (LR/RL): sizes are swapped internally and swapped back.
  let horizontal: Bool

  private struct Vertex {
    var id: String
    var isDummy: Bool
    var w: Double
    var h: Double
    var rank = 0
    var order = 0
    var x: Double = 0
    var y: Double = 0
  }

  func run() -> (centres: [String: CGPoint], routes: [Int: [CGPoint]], size: CGSize) {
    var verts: [Vertex] = vertices.map { id in
      let s = sizes[id] ?? .zero
      return Vertex(id: id, isDummy: false, w: horizontal ? s.height : s.width, h: horizontal ? s.width : s.height)
    }
    var index: [String: Int] = [:]
    for (i, v) in verts.enumerated() { index[v.id] = i }

    // Directed edges between vertex indices (self-loops excluded from layout).
    struct E { var from: Int; var to: Int; var reversed: Bool; var index: Int; var minLength: Int }
    var es: [E] = []
    for e in edges {
      guard let a = index[e.from], let b = index[e.to], a != b else { continue }
      es.append(E(from: a, to: b, reversed: false, index: e.index, minLength: max(1, e.minLength)))
    }

    // 1. Cycle removal by DFS: reverse back edges.
    var state = [Int](repeating: 0, count: verts.count)  // 0 new, 1 active, 2 done
    var adjacency: [[Int]] = Array(repeating: [], count: verts.count)
    for (i, e) in es.enumerated() { adjacency[e.from].append(i) }
    func dfs(_ v: Int) {
      state[v] = 1
      for ei in adjacency[v] {
        let t = es[ei].to
        if state[t] == 1 { es[ei].reversed = true; let f = es[ei].from; es[ei].from = es[ei].to; es[ei].to = f }
        else if state[t] == 0 { dfs(t) }
      }
      state[v] = 2
    }
    for v in verts.indices where state[v] == 0 { dfs(v) }

    // 2. Ranking by longest path (edges may ask for a minimum length).
    var incoming: [[Int]] = Array(repeating: [], count: verts.count)
    var outgoing: [[Int]] = Array(repeating: [], count: verts.count)
    for (i, e) in es.enumerated() { incoming[e.to].append(i); outgoing[e.from].append(i) }
    var indegree = incoming.map(\.count)
    var queue = verts.indices.filter { indegree[$0] == 0 }
    var order: [Int] = []
    while !queue.isEmpty {
      let v = queue.removeFirst()
      order.append(v)
      for ei in outgoing[v] {
        let t = es[ei].to
        verts[t].rank = max(verts[t].rank, verts[v].rank + es[ei].minLength)
        indegree[t] -= 1
        if indegree[t] == 0 { queue.append(t) }
      }
    }
    // Pull sources with a single child down next to it (avoids long dangling edges).
    for v in verts.indices where incoming[v].isEmpty && outgoing[v].count == 1 {
      let t = es[outgoing[v][0]].to
      verts[v].rank = max(verts[v].rank, verts[t].rank - es[outgoing[v][0]].minLength)
    }

    // 3. Dummy vertices for long edges.
    struct Chain { var edge: Int; var vertices: [Int]; var reversed: Bool }
    var chains: [Chain] = []
    var links: [(Int, Int)] = []  // adjacent-rank links used for ordering/coordinates
    for e in es {
      var chain = [e.from]
      var prev = e.from
      let span = verts[e.to].rank - verts[e.from].rank
      if span > 1 {
        for r in (verts[e.from].rank + 1)..<verts[e.to].rank {
          verts.append(Vertex(id: "\u{1}dummy\(verts.count)", isDummy: true, w: 2, h: 2, rank: r))
          let d = verts.count - 1
          links.append((prev, d))
          chain.append(d)
          prev = d
        }
      }
      links.append((prev, e.to))
      chain.append(e.to)
      chains.append(Chain(edge: e.index, vertices: chain, reversed: e.reversed))
    }
    let maxRank = verts.map(\.rank).max() ?? 0
    var layers: [[Int]] = Array(repeating: [], count: maxRank + 1)
    // Initial order: DFS discovery order keeps declaration order roughly intact.
    for v in verts.indices { layers[verts[v].rank].append(v) }
    var up: [[Int]] = Array(repeating: [], count: verts.count)   // neighbours in the previous layer
    var down: [[Int]] = Array(repeating: [], count: verts.count)
    for (a, b) in links { down[a].append(b); up[b].append(a) }

    // 4. Ordering: the weighted-median heuristic with adjacent transposition, keeping the sweep
    // with the fewest crossings. Sorting is stable (position breaks ties) so a layer never churns.
    func positions() -> [Int] {
      var pos = [Int](repeating: 0, count: verts.count)
      for layer in layers { for (i, v) in layer.enumerated() { pos[v] = i } }
      return pos
    }
    func crossings() -> Int {
      let pos = positions()
      var total = 0
      for l in 1..<max(1, layers.count) {
        var pairs: [(Int, Int)] = []
        for v in layers[l] { for u in up[v] { pairs.append((pos[u], pos[v])) } }
        for i in 0..<pairs.count { for j in (i + 1)..<pairs.count where (pairs[i].0 - pairs[j].0) * (pairs[i].1 - pairs[j].1) < 0 { total += 1 } }
      }
      return total
    }
    /// Where a vertex wants to sit: the median of its neighbours in the adjacent layer, biased
    /// towards the denser side when it has an even number of them. -1 keeps it where it is.
    func median(_ v: Int, _ nb: [[Int]], _ pos: [Int]) -> Double {
      let p = nb[v].map { pos[$0] }.sorted()
      guard !p.isEmpty else { return -1 }
      let m = p.count / 2
      if p.count % 2 == 1 { return Double(p[m]) }
      if p.count == 2 { return Double(p[0] + p[1]) / 2 }
      let left = Double(p[m - 1] - p[0]), right = Double(p[p.count - 1] - p[m])
      guard left + right > 0 else { return Double(p[m - 1] + p[m]) / 2 }
      return (Double(p[m - 1]) * right + Double(p[m]) * left) / (left + right)
    }
    /// How many crossings the pair (v, w) contributes, in that order.
    func pairCrossings(_ v: Int, _ w: Int, _ nb: [[Int]], _ pos: [Int]) -> Int {
      var c = 0
      for i in nb[v] { for j in nb[w] where pos[i] > pos[j] { c += 1 } }
      return c
    }
    /// Swaps neighbours while that removes crossings: what the median alone cannot see.
    func transpose() {
      var improved = true
      var rounds = 0
      while improved, rounds < 4 {
        improved = false
        rounds += 1
        for l in layers.indices {
          let pos = positions()
          for i in 0..<max(0, layers[l].count - 1) {
            let v = layers[l][i], w = layers[l][i + 1]
            let keep = pairCrossings(v, w, up, pos) + pairCrossings(v, w, down, pos)
            let swap = pairCrossings(w, v, up, pos) + pairCrossings(w, v, down, pos)
            if swap < keep {
              layers[l].swapAt(i, i + 1)
              improved = true
            }
          }
        }
      }
    }
    var best = layers
    var bestCrossings = crossings()
    for iteration in 0..<8 {
      let pos = positions()
      let sweep = iteration % 2 == 0 ? Array(1..<layers.count) : Array(stride(from: layers.count - 2, through: 0, by: -1))
      let nb = iteration % 2 == 0 ? up : down
      for l in sweep {
        let want = layers[l].map { median($0, nb, pos) }
        let order = layers[l].indices.sorted { a, b in
          let x = want[a], y = want[b]
          if x < 0 || y < 0 || x == y { return a < b }  // no neighbours, or a tie: keep the order
          return x < y
        }
        layers[l] = order.map { layers[l][$0] }
      }
      transpose()
      let c = crossings()
      if c < bestCrossings { bestCrossings = c; best = layers }
      if c == 0 { break }
    }
    layers = best

    // 5. Coordinates. The rank axis comes straight from the layer heights; the other one is the
    // Brandes-Köpf assignment, which is what keeps long edges straight and chains on one line.
    var layerHeights = layers.map { layer in layer.map { verts[$0].h }.max() ?? 0 }
    for i in layerHeights.indices where layerHeights[i] < 10 { layerHeights[i] = 10 }
    var y: Double = 0
    for (l, layer) in layers.enumerated() {
      for v in layer { verts[v].y = y + layerHeights[l] / 2 }
      y += layerHeights[l] + rankSep
    }
    let totalHeight = max(0, y - rankSep)
    let xs = Coordinates(layers: layers, widths: verts.map(\.w), isDummy: verts.map(\.isDummy), up: up, down: down, sep: nodeSep).run()
    for v in verts.indices { verts[v].x = xs[v] }

    // Normalise x to start at 0.
    let minX = verts.map { $0.x - $0.w / 2 }.min() ?? 0
    let maxX = verts.map { $0.x + $0.w / 2 }.max() ?? 0
    for v in verts.indices { verts[v].x -= minX }
    let totalWidth = maxX - minX

    var centres: [String: CGPoint] = [:]
    for v in verts where !v.isDummy { centres[v.id] = point(v.x, v.y) }
    var routes: [Int: [CGPoint]] = [:]
    for chain in chains {
      var pts = chain.vertices.map { point(verts[$0].x, verts[$0].y) }
      if chain.reversed { pts.reverse() }
      routes[chain.edge] = pts
    }
    // Self loops keep an explicit two-point route; the renderer draws the loop.
    for e in edges where e.from == e.to { if let c = centres[e.from] { routes[e.index] = [c, c] } }
    let size = horizontal ? CGSize(width: totalHeight, height: totalWidth) : CGSize(width: totalWidth, height: totalHeight)
    return (centres, routes, size)
  }

  private func point(_ x: Double, _ y: Double) -> CGPoint { horizontal ? CGPoint(x: y, y: x) : CGPoint(x: x, y: y) }
}

/// Brandes-Köpf horizontal coordinate assignment.
///
/// Averaging a vertex against its neighbours and then pushing the layer apart, which is the obvious
/// thing to do, leaves every chain sagging a little further than the last and every long edge bent.
/// This instead aligns each vertex with a *median* neighbour so that the two form a block, compacts
/// the blocks against each other, and does the whole thing from each of the four corners, keeping
/// the average of the two middle answers. Chains come out on one line and long edges come out
/// straight, which is what a layered drawing is read along.
struct Coordinates {
  let layers: [[Int]]
  let widths: [Double]
  let isDummy: [Bool]
  /// Neighbours in the previous and the next layer.
  let up: [[Int]]
  let down: [[Int]]
  let sep: Double

  private var count: Int { widths.count }
  private func key(_ upper: Int, _ lower: Int) -> Int { upper * count + lower }

  func run() -> [Double] {
    let conflicts = type1Conflicts()
    let candidates = [(false, false), (false, true), (true, false), (true, true)].map {
      pass(upward: $0.0, rightward: $0.1, conflicts: conflicts)
    }
    // Line the four up with the narrowest of them — left-biased on the left edge, right-biased on
    // the right — then take the average of the two middle answers.
    let extents = candidates.map { xs -> (lo: Double, hi: Double) in
      var lo = Double.infinity, hi = -Double.infinity
      for v in 0..<count {
        lo = min(lo, xs[v] - widths[v] / 2)
        hi = max(hi, xs[v] + widths[v] / 2)
      }
      return (lo, hi)
    }
    let narrowest = extents.indices.min { extents[$0].hi - extents[$0].lo < extents[$1].hi - extents[$1].lo } ?? 0
    let aligned = candidates.indices.map { i -> [Double] in
      let shift = i % 2 == 0 ? extents[narrowest].lo - extents[i].lo : extents[narrowest].hi - extents[i].hi
      return candidates[i].map { $0 + shift }
    }
    return (0..<count).map { v in
      let four = aligned.map { $0[v] }.sorted()
      return (four[1] + four[2]) / 2
    }
  }

  /// A segment between two dummy vertices is part of a long edge and has to stay straight; where an
  /// ordinary segment crosses one, the ordinary one is marked and gives way during alignment.
  private func type1Conflicts() -> Set<Int> {
    var marked: Set<Int> = []
    guard layers.count > 2 else { return marked }
    var pos = [Int](repeating: 0, count: count)
    for layer in layers { for (i, v) in layer.enumerated() { pos[v] = i } }
    for i in 1..<(layers.count - 1) {
      let lower = layers[i + 1]
      var k0 = 0, scanned = 0
      for l1 in lower.indices {
        let v = lower[l1]
        let inner = isDummy[v] ? up[v].first(where: { isDummy[$0] }) : nil
        guard l1 == lower.count - 1 || inner != nil else { continue }
        let k1 = inner.map { pos[$0] } ?? (layers[i].count - 1)
        while scanned <= l1 {
          for u in up[lower[scanned]] where pos[u] < k0 || pos[u] > k1 { marked.insert(key(u, lower[scanned])) }
          scanned += 1
        }
        k0 = k1
      }
    }
    return marked
  }

  /// One of the four corners: `upward` sweeps from the last layer, `rightward` from the right.
  private func pass(upward: Bool, rightward: Bool, conflicts: Set<Int>) -> [Double] {
    var ls = layers
    if upward { ls.reverse() }
    if rightward { for i in ls.indices { ls[i].reverse() } }
    let previous = upward ? down : up
    var pos = [Int](repeating: 0, count: count)
    var layerOf = [Int](repeating: 0, count: count)
    for (i, layer) in ls.enumerated() { for (j, v) in layer.enumerated() { pos[v] = j; layerOf[v] = i } }

    // Alignment: each vertex joins the block of a median neighbour, as long as that does not cross
    // an alignment already made in this layer or a segment that has to stay straight.
    var root = Array(0..<count), align = Array(0..<count)
    for i in 1..<max(1, ls.count) {
      var placed = -1
      for v in ls[i] {
        let neighbours = previous[v].sorted { pos[$0] < pos[$1] }
        guard !neighbours.isEmpty else { continue }
        let medians = Set([(neighbours.count - 1) / 2, neighbours.count / 2]).sorted()
        for m in medians where align[v] == v {
          let u = neighbours[m]
          let blocked = upward ? conflicts.contains(key(v, u)) : conflicts.contains(key(u, v))
          if !blocked, placed < pos[u] {
            align[u] = v
            root[v] = root[u]
            align[v] = root[v]
            placed = pos[u]
          }
        }
      }
    }

    // Compaction: place each block against the one to its left, and let blocks that meet through a
    // common sink pull each other along rather than pile up.
    var sink = Array(0..<count)
    var shift = [Double](repeating: .infinity, count: count)
    var x = [Double?](repeating: nil, count: count)
    // A dummy vertex is a passing edge, not a box: it needs half the room beside its neighbour.
    func separation(_ a: Int, _ b: Int) -> Double {
      (widths[a] + widths[b]) / 2 + (isDummy[a] || isDummy[b] ? sep / 2 : sep)
    }
    func placeBlock(_ v: Int) {
      guard x[v] == nil else { return }
      x[v] = 0
      var w = v
      repeat {
        if pos[w] > 0 {
          let left = ls[layerOf[w]][pos[w] - 1]
          let u = root[left]
          placeBlock(u)
          if sink[v] == v { sink[v] = sink[u] }
          if sink[v] == sink[u] {
            x[v] = max(x[v]!, x[u]! + separation(left, w))
          } else {
            shift[sink[u]] = min(shift[sink[u]], x[v]! - x[u]! - separation(left, w))
          }
        }
        w = align[w]
      } while w != v
    }
    for v in 0..<count where root[v] == v { placeBlock(v) }
    var out = [Double](repeating: 0, count: count)
    for v in 0..<count {
      out[v] = x[root[v]] ?? 0
      let s = shift[sink[root[v]]]
      if s < .infinity { out[v] += s }
    }
    if rightward { for v in 0..<count { out[v] = -out[v] } }
    return out
  }
}
