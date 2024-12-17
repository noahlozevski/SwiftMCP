import Foundation

public struct CancelledNotification: MCPNotification {
    public static let method = "notifications/cancelled"

    public struct Params: Codable, Sendable {
        public let requestId: RequestID
        public let reason: String?
    }
    public var params: Encodable? { internalParams }

    private let internalParams: Params?

    public init(requestId: RequestID, reason: String? = nil) {
        self.internalParams = Params(requestId: requestId, reason: reason)
    }
}

public struct InitializedNotification: MCPNotification {
    public static let method = "notifications/initialized"

    public struct Params: Codable, Sendable {
        public let _meta: [String: AnyCodable]?
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params?

    public init(_meta: [String: AnyCodable]? = nil) {
        self.internalParams = Params(_meta: _meta)
    }
}

public struct ProgressNotification: MCPNotification {
    public static let method = "notifications/progress"

    public struct Params: Codable, Sendable {
        public let progress: Double
        public let progressToken: AnyCodable
        public let total: Double?
    }
    public var params: Encodable? { internalParams }

    private let internalParams: Params?

    public init(progress: Double, progressToken: Any, total: Double? = nil) {
        self.internalParams = Params(
            progress: progress, progressToken: AnyCodable(progressToken), total: total)
    }
}

public struct RootsListChangedNotification: MCPNotification {
    public static let method = "notifications/roots/list_changed"

    public struct Params: Codable, Sendable {
        public let _meta: [String: AnyCodable]?
    }
    public var params: Encodable? { internalParams }

    private let internalParams: Params?

    public init(_meta: [String: AnyCodable]? = nil) {
        self.internalParams = Params(_meta: _meta)
    }
}

public struct ResourceListChangedNotification: MCPNotification {
    public static let method = "notifications/resources/list_changed"

    public struct Params: Codable, Sendable {
        public let _meta: [String: AnyCodable]?
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params?

    public init(_meta: [String: AnyCodable]? = nil) {
        self.internalParams = Params(_meta: _meta)
    }
}

public struct ResourceUpdatedNotification: MCPNotification {
    public static let method = "notifications/resources/updated"

    public struct Params: Codable, Sendable {
        public let uri: String
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params?

    public init(uri: String) {
        self.internalParams = Params(uri: uri)
    }
}

public struct PromptListChangedNotification: MCPNotification {
    public static let method = "notifications/prompts/list_changed"

    public struct Params: Codable, Sendable {
        public let _meta: [String: AnyCodable]?
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params?

    public init(_meta: [String: AnyCodable]? = nil) {
        self.internalParams = Params(_meta: _meta)
    }
}

public struct ToolListChangedNotification: MCPNotification {
    public static let method = "notifications/tools/list_changed"

    public struct Params: Codable, Sendable {
        public let _meta: [String: AnyCodable]?
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params?

    public init(_meta: [String: AnyCodable]? = nil) {
        self.internalParams = Params(_meta: _meta)
    }
}
