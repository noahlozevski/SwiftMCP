import Foundation

/// Transport implementation using stdio for process-based communication.
/// This transport is designed for long-running MCP servers launched via command line.
public actor StdioTransport: MCPTransport {
  public private(set) var state: TransportState = .disconnected
  public let configuration: TransportConfiguration

  let process: Process
  private let inputPipe = Pipe()
  private let outputPipe = Pipe()
  private let errorPipe = Pipe()
  private var messagesContinuation: AsyncThrowingStream<Data, Error>.Continuation?
  private var processTask: Task<Void, Never>?

  /// Initialize a stdio transport for a command-line MCP server
  /// - Parameters:
  ///   - command: The command to execute (e.g., "npx")
  ///   - arguments: Command arguments (e.g., ["-y", "@modelcontextprotocol/server-git"])
  ///   - environment: Optional environment variables to set
  ///   - configuration: Transport configuration
  public init(
    command: String,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    configuration: TransportConfiguration = .default
  ) {
    self.configuration = configuration
    self.process = Process()

    // Setup executable path and arguments
    self.process.executableURL = URL(fileURLWithPath: "/usr/bin/env")  // Use /usr/bin/env to locate the command in PATH
    self.process.arguments = [command] + arguments

    // Setup environment
    var processEnv = ProcessInfo.processInfo.environment
    // Merge any custom environment variables
    
    environment?.forEach { processEnv[$0] = $1 }

    // Ensure PATH includes common tool locations for npm/npx
    if var path = processEnv["PATH"] {
      let additionalPaths = [
        "/usr/local/bin",
        "/usr/local/npm/bin",
        "\(processEnv["HOME"] ?? "")/node_modules/.bin",  // Local project binaries
        "\(processEnv["HOME"] ?? "")/.npm-global/bin",  // Global npm installs
        "/opt/homebrew/bin",  // Homebrew on Apple Silicon
        "/usr/local/opt/node/bin",  // Node from Homebrew
      ]
      path = (additionalPaths + [path]).joined(separator: ":")
      processEnv["PATH"] = path
    }

    self.process.environment = processEnv

    // Setup pipes
    self.process.standardInput = inputPipe
    self.process.standardOutput = outputPipe
    self.process.standardError = errorPipe
  }

  public func messages() -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      self.messagesContinuation = continuation

      // Auto-start if needed
      Task {
        if self.state == .disconnected {
          do {
            try await self.start()
          } catch {
            continuation.finish(throwing: error)
            return
          }
        }

        // Begin reading messages
        await self.readMessages()
      }

      continuation.onTermination = { [weak self] _ in
        Task { [weak self] in
          await self?.stop()
        }
      }
    }
  }

  public func start() async throws {
    guard state == .disconnected else {
      throw TransportError.invalidState("Transport already started")
    }

    self.state = .connecting

    // Start the process with timeout
    try await with(timeout: .seconds(configuration.connectTimeout)) {
      try self.process.run()

      // Start error monitoring
      await self.monitorErrors()

    }
    self.state = .connected
  }

  public func stop() async {
    processTask?.cancel()
    process.terminate()
    state = .disconnected
    messagesContinuation?.finish()
  }

  public func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
    guard state == .connected else {
      throw TransportError.invalidState("Transport not connected")
    }

    // Check message size
    guard data.count <= configuration.maxMessageSize else {
      throw TransportError.messageTooLarge(data.count)
    }

    // Send with timeout
    try await with(timeout: .seconds(timeout ?? configuration.sendTimeout)) {
      try self.inputPipe.fileHandleForWriting.write(contentsOf: data)
    }
  }

  /// Monitor process stderr for errors
  private func monitorErrors() {
    Task {
      do {
        let handle = errorPipe.fileHandleForReading
        for try await line in handle.bytes.lines {
          // Log but don't fail - some MCP servers use stderr for logging
          print("StdioTransport stderr: \(line)")
        }
      } catch {
        // Only fail if process terminated
        if process.isRunning == false {
          state = .failed(error)
          messagesContinuation?.finish(throwing: error)
        }
      }
    }
  }

  /// Read messages from process stdout
  private func readMessages() async {
    print("Readig messages")
    let handle = outputPipe.fileHandleForReading

    do {
      // Use AsyncBytes for efficient streaming
      for try await data in handle.bytes.lines {
        print("Received data: \(data)")
        guard !Task.isCancelled, let data = data.data(using: .utf8) else {
          break
        }
        messagesContinuation?.yield(data)
      }
      messagesContinuation?.finish()
    } catch {
      state = .failed(error)
      messagesContinuation?.finish(throwing: error)
    }
  }

  /// Helper to find executables in PATH
  private static func findExecutable(_ command: String) -> String? {
    guard let path = ProcessInfo.processInfo.environment["PATH"] else {
      return nil
    }

    let paths = path.split(separator: ":")
    for path in paths {
      let fullPath = "\(path)/\(command)"
      if FileManager.default.isExecutableFile(atPath: fullPath) {
        return fullPath
      }
    }
    return nil
  }
}
