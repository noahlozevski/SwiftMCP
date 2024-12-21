import Foundation
import os.log

public struct StdioTransportOptions {
  public let command: String
  public let arguments: [String]
  public let environment: [String: String]?

  public init(
    command: String,
    arguments: [String] = [],
    environment: [String: String]? = nil
  ) {
    self.command = command
    self.arguments = arguments
    self.environment = environment
  }
}

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
  private let logger = Logger(subsystem: "SwiftMCP", category: "StdioTransport")

  public var isRunning: Bool {
    process.isRunning
  }

  /// Initialize a stdio transport for a command-line MCP server
  /// - Parameters:
  ///   - command: The command to execute (e.g., "npx")
  ///   - arguments: Command arguments (e.g., ["-y", "@modelcontextprotocol/server-git"])
  ///   - environment: Optional environment variables to set
  ///   - configuration: Transport configuration
  public init(
    options: StdioTransportOptions,
    configuration: TransportConfiguration = .default
  ) {
    self.configuration = configuration
    self.process = Process()

    // Setup executable path and arguments
    self.process.executableURL = URL(fileURLWithPath: "/usr/bin/env")  // Use /usr/bin/env to locate the command in PATH
    self.process.arguments = [options.command] + options.arguments

    // Setup environment
    var processEnv = ProcessInfo.processInfo.environment
    // Merge any custom environment variables
    options.environment?.forEach { processEnv[$0] = $1 }

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
      logger.warning("Transport already connected")
      return
    }

    self.state = .connecting

    try process.run()

    self.state = .connected

    Task {
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          await self.monitorStdErr()
        }

        group.addTask {
          await self.readMessages()
        }

        group.addTask {
          self.process.waitUntilExit()
        }
      }
    }
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

    var messageData = data

    logger.debug("Sending message: \(String(data: data, encoding: .utf8) ?? "", privacy: .public)")
    messageData.append(0x0A)  // Append newline

    inputPipe.fileHandleForWriting.write(messageData)
  }

  /// Monitor process stderr for errors
  private func monitorStdErr() async {
    for try await line in errorPipe.bytes.lines {
      // Log but don't fail - some MCP servers use stderr for logging
      logger.info("[SERVER] \(line)")
    }
  }

  /// Read messages from process stdout
  private func readMessages() async {
    for try await data in outputPipe.bytes.lines {
      guard !Task.isCancelled, let data = data.data(using: .utf8) else {
        break
      }
      messagesContinuation?.yield(data)
    }
    messagesContinuation?.finish()
  }
}

extension Pipe {
  struct AsyncBytes: AsyncSequence {
    typealias Element = UInt8

    let pipe: Pipe

    func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
      AsyncStream { continuation in
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
          let data = handle.availableData

          guard !data.isEmpty else {
            continuation.finish()
            return
          }

          for byte in data {
            continuation.yield(byte)
          }
        }

        continuation.onTermination = { _ in
          pipe.fileHandleForReading.readabilityHandler = nil
        }
      }.makeAsyncIterator()
    }
  }

  var bytes: AsyncBytes {
    AsyncBytes(pipe: self)
  }
}
