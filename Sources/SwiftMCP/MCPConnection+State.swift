import Foundation
import Observation

// MARK: - Feature States

@Observable public final class ToolState {
    public private(set) var tools: [MCPTool]
    public private(set) var isRefreshing: Bool
    private let connection: MCPConnection

    init(connection: MCPConnection) {
        self.connection = connection
        self.tools = []
        self.isRefreshing = false
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            tools = try await connection.listTools()
        } catch {
            // Keep existing tools on error
            print("Failed to refresh tools: \(error)")
        }
    }

    public func call(
        _ name: String,
        arguments: [String: Any]? = nil,
        progress: ProgressHandler.UpdateHandler? = nil
    ) async throws -> CallToolResult {
        try await connection.callTool(name, arguments: arguments, progress: progress)
    }
}

@Observable public final class ResourceState {
    public private(set) var resources: [MCPResource]
    public private(set) var isRefreshing: Bool
    private let connection: MCPConnection

    init(connection: MCPConnection) {
        self.connection = connection
        self.resources = []
        self.isRefreshing = false
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            resources = try await connection.listResources()
        } catch {
            print("Failed to refresh resources: \(error)")
        }
    }

    public func read(
        _ uri: String,
        progress: ProgressHandler.UpdateHandler? = nil
    ) async throws -> ReadResourceResult {
        try await connection.readResource(uri, progress: progress)
    }

    public func subscribe(to uri: String) async {
        do {
            try await connection.subscribe(to: uri)
        } catch {
            print("Failed to subscribe to \(uri): \(error)")
        }
    }

    public func unsubscribe(from uri: String) async {
        do {
            try await connection.unsubscribe(from: uri)
        } catch {
            print("Failed to unsubscribe from \(uri): \(error)")
        }
    }

    // Internal update from host
    func update(_ resources: [MCPResource]) {
        self.resources = resources
    }
}

@Observable public final class PromptState {
    public private(set) var prompts: [MCPPrompt]
    public private(set) var isRefreshing: Bool
    private let connection: MCPConnection

    init(connection: MCPConnection) {
        self.connection = connection
        self.prompts = []
        self.isRefreshing = false
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            prompts = try await connection.listPrompts()
        } catch {
            print("Failed to refresh prompts: \(error)")
        }
    }

    public func get(
        _ name: String,
        arguments: [String: String]? = nil,
        progress: ProgressHandler.UpdateHandler? = nil
    ) async throws -> GetPromptResult {
        try await connection.getPrompt(name, arguments: arguments, progress: progress)
    }

    // Internal update from host
    func update(_ prompts: [MCPPrompt]) {
        self.prompts = prompts
    }
}

@Observable public final class RootsState {
    public private(set) var roots: RootsConfig?
    public private(set) var isUpdating: Bool
    private let connection: MCPConnection

    init(connection: MCPConnection) {
        self.connection = connection
        self.roots = nil
        self.isUpdating = false
    }

    public func update(_ config: RootsConfig?) async {
        isUpdating = true
        defer { isUpdating = false }

        do {
            try await connection.updateRoots(config)
        } catch {
            print("Failed to update roots: \(error)")
        }
    }

    // Internal update from host
    func update(_ roots: RootsConfig?) {
        self.roots = roots
    }
}
