import Foundation

/// Root definition
public struct Root: Codable {
    public let uri: String
    public let name: String?
}

public struct ListRootsRequest: MCPRequest {
    public static var method = "roots/list"
    public typealias Response = ListRootsResult

    public struct Params: Codable, Sendable {
        public let _meta: [String: AnyCodable]?
    }
    public var params: Encodable? { internalParams }

    private let internalParams: Params?

    public init() {
        self.internalParams = nil
    }
}

public struct ListRootsResult: MCPResponse {
    public typealias Request = ListRootsRequest

    public let _meta: [String: AnyCodable]?
    public let roots: [Root]
}
