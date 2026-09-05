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

    // 4. Ordering by barycenter sweeps, keeping the best (fewest crossings).
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
    var best = layers
    var bestCrossings = crossings()
    for iteration in 0..<12 {
      let pos = positions()
      if iteration % 2 == 0 {
        for l in 1..<layers.count {
          layers[l].sort { a, b in bary(a, up, pos) < bary(b, up, pos) }
        }
      } else {
        for l in stride(from: layers.count - 2, through: 0, by: -1) {
          layers[l].sort { a, b in bary(a, down, pos) < bary(b, down, pos) }
        }
      }
      let c = crossings()
      if c < bestCrossings { bestCrossings = c; best = layers }
      if c == 0 { break }
    }
    layers = best
    func bary(_ v: Int, _ nb: [[Int]], _ pos: [Int]) -> Double {
      let n = nb[v]
      guard !n.isEmpty else { return Double(pos[v]) }
      return Double(n.map { pos[$0] }.reduce(0, +)) / Double(n.count)
    }

    // 5. Coordinates. y from layer heights; x by packing then averaging neighbours.
    var layerHeights = layers.map { layer in layer.map { verts[$0].h }.max() ?? 0 }
    for i in layerHeights.indices where layerHeights[i] < 10 { layerHeights[i] = 10 }
    var y: Double = 0
    for (l, layer) in layers.enumerated() {
      for v in layer { verts[v].y = y + layerHeights[l] / 2 }
      y += layerHeights[l] + rankSep
    }
    let totalHeight = max(0, y - rankSep)
    // Initial packing.
    for layer in layers {
      var x: Double = 0
      for v in layer {
        verts[v].x = x + verts[v].w / 2
        x += verts[v].w + nodeSep
      }
    }
    func resolve(_ layer: [Int]) {
      // Enforce minimum separation left-to-right, then centre the layer as a whole.
      for i in 1..<max(1, layer.count) {
        let a = layer[i - 1], b = layer[i]
        let minX = verts[a].x + verts[a].w / 2 + nodeSep + verts[b].w / 2
        if verts[b].x < minX { verts[b].x = minX }
      }
      for i in stride(from: layer.count - 2, through: 0, by: -1) {
        let a = layer[i], b = layer[i + 1]
        let maxX = verts[b].x - verts[b].w / 2 - nodeSep - verts[a].w / 2
        if verts[a].x > maxX { verts[a].x = maxX }
      }
    }
    for _ in 0..<6 {
      for l in 1..<layers.count {
        for v in layers[l] where !up[v].isEmpty { verts[v].x = up[v].map { verts[$0].x }.reduce(0, +) / Double(up[v].count) }
        resolve(layers[l])
      }
      for l in stride(from: layers.count - 2, through: 0, by: -1) {
        for v in layers[l] where !down[v].isEmpty {
          let target = down[v].map { verts[$0].x }.reduce(0, +) / Double(down[v].count)
          verts[v].x = (verts[v].x + target) / 2
        }
        resolve(layers[l])
      }
    }
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
