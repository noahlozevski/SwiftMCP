import Foundation

/// A JSON-RPC 2.0 message in the MCP protocol.
///
/// It can be a request, response, error, or notification.
/// Requests and responses are strongly typed thanks to generics.
public enum JSONRPCMessage<Request: MCPRequest>: Codable {
    /// JSON-RPC version constant
    public var jsonrpcVersion: String { "2.0" }

    /// A request message expecting a response.
    case request(id: RequestID, request: Request)

    /// A successful response message.
    case response(id: RequestID, response: Request.Response)

    /// An error response message.
    case error(id: RequestID, error: MCPError)

    /// A notification message that doesn't expect a response.
    case notification(MCPNotification)

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params, result, error
    }

    public func encode(to encoder: Encoder) throws {
        try validateVersion()

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpcVersion, forKey: .jsonrpc)

        switch self {
        case .request(let id, let request):
            try container.encode(id, forKey: .id)
            try container.encode(type(of: request).method, forKey: .method)
            if let params = request.params {
                try container.encodeAny(params, forKey: .params)
            }
        case .response(let id, let response):
            try container.encode(id, forKey: .id)
            try container.encode(response, forKey: .result)
        case .error(let id, let error):
            try container.encode(id, forKey: .id)
            try container.encode(error, forKey: .error)
        case .notification(let notification):
            try container.encode(type(of: notification).method, forKey: .method)
            if let params = notification.params {
                try container.encodeAny(params, forKey: .params)
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        if let id = try container.decodeIfPresent(RequestID.self, forKey: .id) {
            // Could be request, response, or error
            if let errorVal = try container.decodeIfPresent(MCPError.self, forKey: .error) {
                self = .error(id: id, error: errorVal)
            } else if let resultVal = try? container.decode(Request.Response.self, forKey: .result) {
                self = .response(id: id, response: resultVal)
            } else {
                // Must be a request
                let method = try container.decode(String.self, forKey: .method)
                // Decoding a generic request requires method-based dispatch.
                // For simplicity, we assume Request is known at runtime or use a factory.
                let paramsAny = try container.decodeIfPresent(
                    [String: AnyCodable].self, forKey: .params)
                guard let req = RequestFactory.makeRequest(method: method, params: paramsAny) else {
                    throw MCPError.methodNotFound(method)
                }
                guard let req = req as? Request else {
                    throw MCPError.invalidRequest("Invalid request type")
                }
                self = .request(id: id, request: req)
            }
        } else {
            // Notification
            let method = try container.decode(String.self, forKey: .method)
            let paramsAny = try container.decodeIfPresent(
                [String: AnyCodable].self, forKey: .params)
            guard
                let notif = NotificationFactory.makeNotification(method: method, params: paramsAny)
            else {
                throw MCPError.methodNotFound(method)
            }
            self = .notification(notif)
        }

        try validateRPCVersion(jsonrpc)
        try validateVersion()
    }

    private func validateRPCVersion(_ version: String) throws {
        guard version == jsonrpcVersion else {
            throw MCPError.invalidRequest("Invalid JSON-RPC version")
        }
    }
}

struct EmptyRequest: MCPRequest {
    typealias Response = EmptyResult

    var params: (any Encodable)? { nil }

    static let method = "empty"
}

struct EmptyResult: MCPResponse {
    typealias Request = EmptyRequest
}

extension JSONRPCMessage where Request == EmptyRequest, Request.Response == EmptyResult {
    init(notification: MCPNotification) {
        self = .notification(notification)
    }

    init(id: RequestID, error: MCPError) {
        self = .error(id: id, error: error)
    }
}

extension JSONRPCMessage: MCPMessage {}
