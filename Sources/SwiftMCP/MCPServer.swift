import Foundation

public protocol MCPServerProtocol {

}

// public struct MCPServerFeature: OptionSet {
//   public let rawValue: UInt
//
// }

public struct MCPServerConfiguration {
  public let implementation: Implementation
  public let capabilities: ServerCapabilities

}
