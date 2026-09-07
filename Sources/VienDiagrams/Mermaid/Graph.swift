import CoreGraphics
import Foundation

/// Node/edge/cluster model shared by flowcharts, class diagrams and state diagrams.
public struct GraphDiagram: Sendable {
  public enum Direction: String, Sendable {
    case TB, BT, LR, RL
    /// The same flow turned a quarter: what a graph too wide for its measure is laid out along instead.
    public var turned: Direction {
      switch self {
      case .TB: return .LR
      case .BT: return .RL
      case .LR: return .TB
      case .RL: return .BT
      }
    }
  }

  public enum Shape: Sendable, Equatable {
    case rect, rounded, stadium, subroutine, cylinder, circle, doubleCircle, asymmetric, diamond, hexagon
    case parallelogram, parallelogramAlt, trapezoid, trapezoidAlt
    /// State diagram start (filled dot) and end (bullseye).
    case start, end
    /// Class box with compartments (`compartments` holds the lines).
    case classBox
    case note
  }

  public struct NodeStyle: Sendable, Equatable {
    public var fill: DiagramColor?
    public var stroke: DiagramColor?
    public var strokeWidth: Double?
    public var color: DiagramColor?
    public var dashed = false
    public init() {}
  }

  public struct Node: Sendable {
    public var id: String
    public var label: String
    public var shape: Shape
    public var style: NodeStyle?
    public var classes: [String] = []
    /// Class diagrams: [annotation+name], [attributes], [methods].
    public var compartments: [[String]] = []
    public var cluster: String?
    public init(id: String, label: String, shape: Shape = .rect) {
      self.id = id
      self.label = label
      self.shape = shape
    }
  }

  public enum ArrowHead: Sendable, Equatable {
    case none, arrow, circle, cross, triangle, diamond, diamondFilled
    /// Entity-relationship cardinalities (crow's foot).
    case erOne, erZeroOrOne, erZeroOrMore, erOneOrMore
  }
  public enum LineStyle: Sendable, Equatable { case solid, dotted, thick, invisible }

  public struct Edge: Sendable {
    public var from: String
    public var to: String
    public var label: String?
    public var head: ArrowHead = .arrow
    public var tail: ArrowHead = .none
    public var line: LineStyle = .solid
    /// Minimum number of ranks the edge should span (`-->` = 1, `---->` = 2 …).
    public var minLength = 1
    public init(from: String, to: String) { self.from = from; self.to = to }
  }

  public struct Cluster: Sendable {
    public var id: String
    public var title: String?
    public var parent: String?
    public var direction: Direction?
    public var style: NodeStyle?
  }

  public var direction: Direction = .TB
  public var nodes: [Node] = []
  public var edges: [Edge] = []
  public var clusters: [Cluster] = []
  public var classDefs: [String: NodeStyle] = [:]
  public var title: String?

  public init() {}

  mutating func node(_ id: String, label: String? = nil, shape: Shape? = nil, cluster: String? = nil) {
    if let i = nodes.firstIndex(where: { $0.id == id }) {
      if let label { nodes[i].label = label }
      if let shape { nodes[i].shape = shape }
      if let cluster, nodes[i].cluster == nil { nodes[i].cluster = cluster }
    } else {
      var n = Node(id: id, label: label ?? id, shape: shape ?? .rect)
      n.cluster = cluster
      nodes.append(n)
    }
  }

  func node(withID id: String) -> Node? { nodes.first { $0.id == id } }

  /// Effective style of a node: explicit style over class definitions.
  func effectiveStyle(_ node: Node) -> NodeStyle? {
    var style = NodeStyle()
    var any = false
    for c in node.classes {
      if let d = classDefs[c] { merge(&style, d); any = true }
    }
    if let s = node.style { merge(&style, s); any = true }
    return any ? style : nil
  }

  private func merge(_ into: inout NodeStyle, _ from: NodeStyle) {
    if let f = from.fill { into.fill = f }
    if let s = from.stroke { into.stroke = s }
    if let w = from.strokeWidth { into.strokeWidth = w }
    if let c = from.color { into.color = c }
    if from.dashed { into.dashed = true }
  }
}

extension GraphDiagram.NodeStyle {
  /// Parses `fill:#f9f,stroke:#333,stroke-width:4px,color:#fff,stroke-dasharray: 5 5`.
  static func parse(_ css: String) -> GraphDiagram.NodeStyle {
    var s = GraphDiagram.NodeStyle()
    for part in css.split(separator: ",") {
      let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      guard kv.count == 2 else { continue }
      switch kv[0] {
      case "fill": s.fill = DiagramColor(css: kv[1])
      case "stroke": s.stroke = DiagramColor(css: kv[1])
      case "color": s.color = DiagramColor(css: kv[1])
      case "stroke-width": s.strokeWidth = Double(kv[1].replacingOccurrences(of: "px", with: ""))
      case "stroke-dasharray": s.dashed = true
      default: break
      }
    }
    return s
  }
}
