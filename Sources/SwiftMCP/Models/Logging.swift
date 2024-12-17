import Foundation

public enum LoggingLevel: String, Codable, Sendable {
    case alert, critical, debug, emergency, error, info, notice, warning
}

public struct SetLevelRequest: MCPRequest {
    public static let method = "logging/setLevel"
    public typealias Response = EmptyResult

    public struct Params: Codable, Sendable {
        public let level: LoggingLevel
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params

    public init(level: LoggingLevel) {
        self.internalParams = Params(level: level)
    }
    /// Empty result since just a confirmation is needed.
    public struct EmptyResult: MCPResponse {
        public typealias Request = SetLevelRequest
    }
}

public struct LoggingMessageNotification: MCPNotification {
    public static let method = "notifications/message"

    public struct Params: Codable, Sendable {
        public let data: AnyCodable
        public let level: LoggingLevel
        public let logger: String?
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params

    public init(data: Any, level: LoggingLevel, logger: String? = nil) {
        self.internalParams = Params(data: AnyCodable(data), level: level, logger: logger)
    }
}
