import Foundation

public struct CompleteRequest: MCPRequest {
    public static let method = "completion/complete"
    public typealias Response = CompleteResult

    public struct Params: Codable, Sendable {
        public let argument: Argument
        public let ref: Reference

        public struct Argument: Codable, Sendable {
            public let name: String
            public let value: String
        }

        public enum Reference: Codable, Sendable {
            case prompt(PromptRef)
            case resource(ResourceRef)

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let promptRef = try? container.decode(PromptRef.self),
                    promptRef.type == "ref/prompt"
                {
                    self = .prompt(promptRef)
                    return
                }
                if let resourceRef = try? container.decode(ResourceRef.self),
                    resourceRef.type == "ref/resource"
                {
                    self = .resource(resourceRef)
                    return
                }
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown reference type")
            }

            public func encode(to encoder: Encoder) throws {
                switch self {
                case .prompt(let promptRef): try promptRef.encode(to: encoder)
                case .resource(let resourceRef): try resourceRef.encode(to: encoder)
                }
            }
        }

        public struct PromptRef: Codable, Sendable {
            public let name: String
            public let type = "ref/prompt"
        }

        public struct ResourceRef: Codable, Sendable {
            public let uri: String
            public let type = "ref/resource"
        }
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params

    public init(argument: Params.Argument, ref: Params.Reference) {
        self.internalParams = Params(argument: argument, ref: ref)
    }
}

public struct CompleteResult: MCPResponse {
    public typealias Request = CompleteRequest

    public struct Completion: Codable, Sendable {
        public let values: [String]
        public let hasMore: Bool?
        public let total: Int?
    }

    public let completion: Completion
    public let _meta: [String: AnyCodable]?
}
