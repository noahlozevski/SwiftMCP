import Foundation

public enum MCPVersion {
  static let currentVersion = "2024-11-05"
  public static let supportedVersions = ["2024-11-05", "2024-10-07"]
}

/// Core protocol marker for all MCP messages
public protocol MCPMessage: Codable, Sendable {
  /// Protocol version for this message
  static var supportedVersions: [String] { get }
  
  /// Current protocol version
  static var currentVersion: String { get }
  
  /// Version validation
  func validateVersion() throws
}

extension MCPMessage {
  public static var currentVersion: String { MCPVersion.currentVersion }
  public static var supportedVersions: [String] { MCPVersion.supportedVersions }
  
  public func validateVersion() throws {
    if !Self.supportedVersions.contains(Self.currentVersion) {
      throw MCPError.invalidRequest("Unsupported protocol version \(Self.currentVersion)")
    }
  }
}

/// Protocol for request messages.
///
/// Conforming types specify a request method, associated response type, and parameters.
public protocol MCPRequest: MCPMessage {
  associatedtype Response: MCPResponse where Response.Request == Self
  
  /// The JSON-RPC method name for this request.
  static var method: String { get }
  
  /// The request parameters, if any.
  var params: Encodable? { get }
}

/// Protocol for response messages
public protocol MCPResponse: MCPMessage {
  /// The request type this response corresponds to
  associatedtype Request: MCPRequest where Request.Response == Self
}

/// Protocol for notification messages
public protocol MCPNotification: MCPMessage {
  /// The method name for this notification
  static var method: String { get }
  
  /// The parameters for this notification, if any
  var params: Encodable? { get }
}
