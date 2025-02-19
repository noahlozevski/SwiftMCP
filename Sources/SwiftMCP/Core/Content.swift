import Foundation

public struct TextContent: Codable, Sendable, Hashable {
    public let text: String
    public var type: String = "text"
    public let annotations: Annotations?
}

public struct ImageContent: Codable, Sendable, Hashable {
    public let data: String
    public let mimeType: String
    public var type: String = "image"
    public let annotations: Annotations?

}

public enum Role: String, Codable, Sendable {
    case assistant
    case user
}

public struct Annotations: Codable, Sendable, Hashable {
    public let audience: [Role]?
    public let priority: Double?
}
public struct TextResourceContents: Codable, Sendable, Hashable {
    public let uri: String
    public let mimeType: String?
    public let text: String
}

public struct BlobResourceContents: Codable, Sendable, Hashable {
    public let blob: String
    public let uri: String
    public let mimeType: String?
}

/// EmbeddedResource can be either text or blob:
public enum ResourceContentVariant: Codable, Sendable, Hashable {
    case text(TextResourceContents)
    case blob(BlobResourceContents)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Try text first:
        if let textResource = try? container.decode(TextResourceContents.self) {
            // must have text present
            if textResource.text.isEmpty {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "TextResourceContents must have text")
            }
            self = .text(textResource)
            return
        }
        // Try blob
        if let blobResource = try? container.decode(BlobResourceContents.self) {
            self = .blob(blobResource)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Resource must be either TextResourceContents or BlobResourceContents"
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let textResource): try textResource.encode(to: encoder)
        case .blob(let blobResource): try blobResource.encode(to: encoder)
        }
    }
}

public struct EmbeddedResourceContent: Codable, Sendable, Hashable {
    public var type: String = "resource"
    public let annotations: Annotations?
    public let resource: ResourceContentVariant
}
