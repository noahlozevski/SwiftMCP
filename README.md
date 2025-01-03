# SwiftMCP

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%2013+%20|%20iOS%2016+-lightgray.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

SwiftMCP is a work-in-progress Swift implementation of the Model Context Protocol (MCP), aiming to provide a robust and type-safe way to integrate Language Model capabilities into Swift applications.

> ⚠️ Note: This SDK is under active development. APIs may change as we work towards feature parity with the TypeScript implementation.


## Features

- 🏃 **Modern Swift Concurrency** - Built with Swift's actor model and async/await
- 🔒 **Type-Safe** - Full type safety for all MCP messages and operations
- 🔌 **Multiple Transports** - Support for stdio and Server-Sent Events (SSE)
- ⚡️ **Performance** - Efficient message handling with timeout and retry support
- 🛠 **Rich Capabilities** - Support for resources, prompts, tools, and more
- 📦 **SwiftPM Ready** - Easy integration through Swift Package Manager

## Installation

Add SwiftMCP to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/gavinaboulhosn/SwiftMCP.git", branch: "main")
]
```

Or add it to your Xcode project:
1. File > Add Package Dependencies
2. Enter: `https://github.com/gavinaboulhosn/SwiftMCP.git`

## Basic Usage

### Creating a Client

```swift
import SwiftMCP

// Initialize client
let client = MCPClient(
    clientInfo: .init(name: "MyApp", version: "1.0.0"),
    capabilities: .init(
        roots: .init(listChanged: true)  // Enable roots with change notifications
    )
)

// Connect using stdio transport
let transport = StdioTransport(
    options: .init(
        command: "npx",
        arguments: ["-y", "@modelcontextprotocol/server-memory"]
    )
)

// Start the client
try await client.start(transport)

// Make requests
let resources = try await client.listResources()
print("Found \(resources.resources.count) resources")

// Listen for notifications
for await notification in await client.notifications {
    switch notification {
    case let resourceUpdate as ResourceUpdatedNotification:
        print("Resource updated: \(resourceUpdate.params?.uri ?? "")")
    default:
        break
    }
}
```

### Hosts
Hosts are used to manage client connections and provide a higher-level API for handling requests and notifications:

#### Basic Setup

To get started, you need to create an `MCPHost` instance and connect to a server using a transport layer:

```swift
import SwiftMCP

// Basic host - assumes app name and version via Bundle properties
let host = MCPHost()
// or more advanced configuration
let host = MCPHost(config:
    .init(
        roots: .list([Root(uri: "file:///some/root")]),
        sampling: .init(
            handler: { request in
                /** Use your llm to fulfill the server's sampling request */
                let completion = try await myLLM.complete(
                    messages: request.messages,
                    // other options
                )
                return CreateMessageResult( /** the result */)

                // or reject the request
                throw Error.notAllowed
            }),
        clientInfo: /** your explicit client info */,
        capabilities: /** Your explicit client capabilities (inferred by default from what root / sampling config is provided) */

    )
)

let transport = StdioTransport(command: "npx", arguments: ["-y", "@modelcontextprotocol/server-everything"])

let connection = try await host.connect("test", transport: transport)
```

#### Sending Requests

```swift
let tools = try await connection.listTools()

print("Available tools: \(tools.tools)")
```

#### Handling Notifications

Notifications can be handled by subscribing to the `notifications` stream:

> Note: The connection automatically observes server notifications and will update tools, resources, and prompts accordingly. You only need to observe notifications if you want to handle them directly in your application code.


```swift
let notificationStream = await connection.notifications
for await notification in notificationStream {
    switch notification {
    case let toolChanged as ToolListChangedNotification:
        print("Tool list changed: \(toolChanged)")
    default:
        break
    }
}
```

#### Progress Tracking

For long-running operations, you can track progress using a progress handler:

```swift
let _ = try await connection.callTool(
    "longRunningOperation",
    arguments: ["duration": 5, "steps": 10]) { progress, total in
        print("Progress: \(progress) / \(total ?? 0)")
    }
```


#### Error Handling

SwiftMCP provides structured error handling:

```swift
do {
    try await client.start(transport)
} catch let error as MCPError {
    switch error.code {
    case .connectionClosed:
        print("Connection closed: \(error.message)")
    case .invalidRequest:
        print("Invalid request: \(error.message)")
    default:
        print("Error: \(error)")
    }
}
```

## Advanced Features

### Custom Transport

Implement your own transport by conforming to `MCPTransport`:

```swift
actor MyCustomTransport: MCPTransport {
    var state: TransportState = .disconnected
    let configuration: TransportConfiguration
    
    func messages() -> AsyncThrowingStream<Data, Error> {
        // Implement message streaming
    }
    
    func start() async throws {
        // Initialize transport
    }
    
    func stop() async {
        // Cleanup
    }
    
    func send(_ data: Data, timeout: TimeInterval?) async throws {
        // Send message
    }
}
```

### Request Timeout & Retry

Configure timeout and retry policies:

```swift
let transport = StdioTransport(
    options: .init(command: "server"),
    configuration: .init(
        connectTimeout: 30.0,
        sendTimeout: 10.0,
        retryPolicy: .init(
            maxAttempts: 3,
            baseDelay: 1.0,
            backoffPolicy: .exponential
        )
    )
)
```

## API Documentation

Visit [modelcontextprotocol.io](https://modelcontextprotocol.io) for full protocol documentation.

Key types and protocols:

- `MCPHost`: Host interface
- `MCPClient`: Main client interface
- `MCPTransport`: Transport abstraction
- `MCPMessage`: Base message protocol
- `MCPRequest`/`MCPResponse`: Request/response protocols
- `MCPNotification`: Notification protocol


## Roadmap

- ✅ Base protocol with JSON-RPC message handling
- ✅ Core transports: stdio and SSE
- ✅ Actor-based architecture with SwiftConcurrency
- ✅ Type-safe requests and responses
- ✅ Basic error handling and timeouts
- ✅ Client implementation with transport abstraction
- ✅ Host implementation improvements
- ✅ Enhanced sampling capabilities
- ✅ Progress monitoring enhancements
- 🚧 WebSocket transport
- 🚧 MCP Server implementation
- 🚧 Example servers and implementations

## Contributing

1. Read the [MCP Specification](https://spec.modelcontextprotocol.io)
2. Fork the repository
3. Create a feature branch
4. Add tests for new functionality
5. Submit a pull request

## Limitations
- StdioTransport does not work in sandboxed environments

### Development

```bash
# Clone repository
git clone https://github.com/gavinaboulhosn/SwiftMCP.git

# Build
swift build

# Run tests
swift test
```

