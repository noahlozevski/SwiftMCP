import Foundation
import Testing

@testable import SwiftMCP

@Suite("MCP Serialization Tests")
struct MCPSerializationTests {

    @Test("Decode Initialize Request")
    func decodeInitializeRequest() throws {
        let initializeRequestJSON = """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "method": "initialize",
              "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                  "roots": {
                    "listChanged": true
                  },
                  "sampling": {},
                  "experimental": {
                    "featureX": {
                      "enabled": true
                    }
                  }
                },
                "clientInfo": {
                  "name": "ExampleClient",
                  "version": "1.0.0"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage<InitializeRequest>.self, from: initializeRequestJSON)

        guard case .request(let id, let req) = message else {
            Issue.record("Expected a request message")
            return
        }

        try #require(id == .int(1))
        try #require(type(of: req).method == "initialize")

        let params = try #require(req.params) as! InitializeRequest.Params
        try #require(params.protocolVersion == "2024-11-05")
        try #require(params.clientInfo.name == "ExampleClient")
        try #require(params.clientInfo.version == "1.0.0")
        try #require(params.capabilities.roots?.listChanged == true)
    }

    @Test("Decode Initialize Response")
    func decodeInitializeResponse() throws {
        let initializeResponseJSON = """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                  "logging": {},
                  "prompts": {
                    "listChanged": true
                  },
                  "resources": {
                    "subscribe": true,
                    "listChanged": true
                  },
                  "tools": {
                    "listChanged": true
                  }
                },
                "serverInfo": {
                  "name": "ExampleServer",
                  "version": "2.3.1"
                },
                "instructions": "Use this server to access code prompts and resources.",
                "_meta": {
                  "sessionId": "abc123"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage<InitializeRequest>.self, from: initializeResponseJSON)

        guard case .response(let id, let resp) = message else {
            Issue.record("Expected a response message")
            return
        }

        try #require(id == .int(1))
        try #require(resp.protocolVersion == "2024-11-05")
        try #require(resp.serverInfo.name == "ExampleServer")
        try #require(resp.serverInfo.version == "2.3.1")
        try #require(resp.instructions == "Use this server to access code prompts and resources.")

        let capabilities = resp.capabilities
        try #require(capabilities.tools?.listChanged == true)
    }

    @Test("Decode List Resources Request")
    func decodeListResourcesRequest() throws {
        let listResourcesRequestJSON = """
            {
              "jsonrpc": "2.0",
              "id": 30,
              "method": "resources/list",
              "params": {
                "cursor": "page1"
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage<ListResourcesRequest>.self,
            from: listResourcesRequestJSON)

        guard case .request(_, let req) = message else {
            Issue.record("Expected a request message")
            return
        }

        let params = req.params as? ListResourcesRequest.Params
        if let params = params {
            try #require(params.cursor == "page1")
        } else {
            Issue.record("params is nil, expected a cursor")
        }
    }

    @Test("Decode List Resources Response")
    func decodeListResourcesResponse() throws {
        let listResourcesResponseJSON = """
            {
              "jsonrpc": "2.0",
              "id": 30,
              "result": {
                "resources": [
                  {
                    "uri": "file:///project/src/main.rs",
                    "name": "main.rs",
                    "description": "Rust main file",
                    "mimeType": "text/x-rust"
                  }
                ],
                "nextCursor": "page2",
                "_meta": {
                  "count": "1"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage<ListResourcesRequest>.self,
            from: listResourcesResponseJSON)

        guard case .response(_, let resp) = message else {
            Issue.record("Expected a response message")
            return
        }

        try #require(resp.resources.count == 1)
        let resource = try #require(resp.resources.first)
        try #require(resource.uri == "file:///project/src/main.rs")
        try #require(resource.name == "main.rs")
        try #require(resp.nextCursor == "page2")
    }

    @Test("Decode Call Tool Request")
    func decodeCallToolRequest() throws {
        let callToolRequestJSON = """
            {
              "jsonrpc": "2.0",
              "id": 21,
              "method": "tools/call",
              "params": {
                "name": "get_weather",
                "arguments": {
                  "location": "New York"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage<CallToolRequest>.self, from: callToolRequestJSON)

        guard case .request(_, let req) = message else {
            Issue.record("Expected a request message")
            return
        }

        let params = try #require(req.params) as! CallToolRequest.Params
        try #require(params.name == "get_weather")
        try #require((params.arguments["location"]?.value as? String) == "New York")
    }

    @Test("Decode Call Tool Result")
    func decodeCallToolResult() throws {
        let callToolResultJSON = """
            {
              "jsonrpc": "2.0",
              "id": 21,
              "result": {
                "content": [
                  {
                    "type": "text",
                    "text": "Current weather in New York: 75°F, partly cloudy"
                  }
                ],
                "isError": false
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage<CallToolRequest>.self, from: callToolResultJSON)

        guard case .response(_, let resp) = message else {
            Issue.record("Expected a response message")
            return
        }

        try #require(resp.isError == false)
        try #require(resp.content.count == 1)
        if case let .text(textContent) = resp.content.first! {
            try #require(textContent.text.contains("New York"))
        } else {
            Issue.record("Expected text content in the tool result")
        }
    }

    @Test("Decode Cancelled Notification")
    func decodeCancelledNotification() throws {
        let cancelledNotificationJSON = """
            {
              "jsonrpc": "2.0",
              "method": "notifications/cancelled",
              "params": {
                "requestId": 42,
                "reason": "User aborted the operation"
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage<InitializeRequest>.self,
            from: cancelledNotificationJSON)

        guard case .notification(let notif) = message else {
            Issue.record("Expected a notification message")
            return
        }

        if let cancelledNotification = notif as? CancelledNotification {
            let params = try #require(cancelledNotification.params) as? CancelledNotification.Params
            try #require(params?.requestId == .int(42))
            try #require(params?.reason == "User aborted the operation")
        } else {
            Issue.record("Notification is not a CancelledNotification")
        }
    }

    @Test("Decode Prompt List Changed Notification")
    func decodePromptListChangedNotification() throws {
        let promptListChangedNotificationJSON = """
            {
              "jsonrpc": "2.0",
              "method": "notifications/prompts/list_changed",
              "params": {
                "_meta": {
                  "reason": "new prompts added"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage<InitializeRequest>.self,
            from: promptListChangedNotificationJSON)

        guard case .notification(let notif) = message else {
            Issue.record("Expected a notification message")
            return
        }

        if let promptListChangedNotification = notif as? PromptListChangedNotification {
            let params =
                promptListChangedNotification.params as? PromptListChangedNotification.Params
            if let meta = params?._meta {
                try #require((meta["reason"]?.value as? String) == "new prompts added")
            } else {
                Issue.record("Missing _meta in prompt list changed notification params")
            }
        } else {
            Issue.record("Notification is not a PromptListChangedNotification")
        }
    }
}
