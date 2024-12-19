import Foundation
import Testing

@testable import SwiftMCP

// Need to run serially cause flakiness
@Suite("Stdio Transport Tests", .serialized)
struct StdioTransportTests {

  @Test("Creates transport with proper environment setup")
  func testEnvironmentSetup() async throws {
    let transport = StdioTransport(
      command: "echo",
      arguments: ["test"],
      environment: ["TEST_VAR": "value"]
    )

    let processEnv = (await transport.process).environment

    // Should have test var
    #expect(processEnv?["TEST_VAR"] == "value")

    // Should have expanded PATH
    let path = try #require(processEnv?["PATH"])
    #expect(path.contains("/usr/local/bin"))
    #expect(path.contains("/usr/local/npm/bin"))
  }

  @Test("Handles echo command with auto-start from messages")
  func testEchoCommand() async throws {
    let transport = StdioTransport(
      command: "echo",
      arguments: ["test"]
    )

    var messages = [Data]()
    let messagesTask = Task {
      // This should auto-start the transport
      for try await message in await transport.messages() {
        messages.append(message)
      }
    }

    // Wait briefly for process to complete
    try await Task.sleep(for: .milliseconds(100))
    await transport.stop()
    try await messagesTask.value

    let output = try messages.map { try #require(String(data: $0, encoding: .utf8)) }.joined()
    #expect(output.trimmingCharacters(in: .whitespacesAndNewlines).contains("test"))
  }

  @Test("Handles npx command execution")
  func testNpxCommand() async throws {
    let transport = StdioTransport(
      command: "npx",
      arguments: ["-y", "cowsay", "test"]
    )

    var output = Data()
    let messagesTask = Task {
      for try await message in await transport.messages() {
        output.append(message)
      }
    }

    // Wait for command output
    try await Task.sleep(for: .milliseconds(1000))
    await transport.stop()
    try await messagesTask.value

    let outputString = try #require(String(data: output, encoding: .utf8))
    #expect(outputString.contains("test"))
  }
}
