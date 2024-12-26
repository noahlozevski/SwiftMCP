import Foundation

public struct PingRequest: MCPRequest {
    public static let method = "ping"
    public typealias Response = EmptyResult

    public struct Params: Codable, Sendable {
        public init() {}
    }
    public var params: Encodable? { Params() }

    public init() {}

    public struct EmptyResult: MCPResponse {
        public typealias Request = PingRequest
    }
}
