import Foundation

/// Configuration for transport connection behavior
public struct TransportConfiguration {
    /// Maximum time to wait for connection in seconds
    public let connectTimeout: TimeInterval

    /// Maximum time to wait for a message send in seconds
    public let sendTimeout: TimeInterval

    /// Maximum message size in bytes
    public let maxMessageSize: Int

    /// Retry policy for failed operations
    public let retryPolicy: TransportRetryPolicy

    public init(
        connectTimeout: TimeInterval = 30.0,
        sendTimeout: TimeInterval = 30.0,
        maxMessageSize: Int = 1024 * 1024 * 4,  // 4MB default
        retryPolicy: TransportRetryPolicy = .default
    ) {
        self.connectTimeout = connectTimeout
        self.sendTimeout = sendTimeout
        self.maxMessageSize = maxMessageSize
        self.retryPolicy = retryPolicy
    }

    public static let `default` = TransportConfiguration()
}

/// Policy for retrying failed operations
public struct TransportRetryPolicy {
    /// Maximum number of retry attempts
    public let maxAttempts: Int

    /// Base delay between retries in seconds
    public let baseDelay: TimeInterval

    /// Maximum delay between retries in seconds
    public let maxDelay: TimeInterval

    /// Jitter factor to add randomness to delays (0.0-1.0)
    public let jitter: Double

    /// Backoff policy for increasing delays between retries
    public let backoffPolicy: BackoffPolicy

    public enum BackoffPolicy {
        /// Fixed delay between attempts
        case constant

        /// Exponential backoff with optional jitter
        case exponential

        /// Linear backoff with optional jitter
        case linear

        /// Custom backoff function
        case custom((Int) -> TimeInterval)

        func delay(attempt: Int, baseDelay: TimeInterval, jitter: Double = 0) -> TimeInterval {
            let rawDelay: TimeInterval

            switch self {
            case .constant:
                rawDelay = baseDelay

            case .exponential:
                rawDelay = baseDelay * pow(2.0, Double(attempt - 1))

            case .linear:
                rawDelay = baseDelay * Double(attempt)

            case .custom(let calculator):
                rawDelay = calculator(attempt)
            }

            // Add jitter if specified
            if jitter > 0 {
                let jitterRange = rawDelay * jitter
                let randomJitter = Double.random(in: -jitterRange...jitterRange)
                return max(0, rawDelay + randomJitter)
            }
            return rawDelay
        }
    }

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        jitter: Double = 0.1,
        backoffPolicy: BackoffPolicy = .exponential
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
        self.backoffPolicy = backoffPolicy
    }

    public static let `default` = TransportRetryPolicy()

    /// Calculate delay for a given attempt
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let raw = backoffPolicy.delay(attempt: attempt, baseDelay: baseDelay, jitter: jitter)
        return min(raw, maxDelay)
    }
}

/// A transport connection state
public enum TransportState {

    /// Transport is disconnected
    case disconnected

    /// Transport is connecting
    case connecting

    /// Transport is connected and ready
    case connected

    /// Transport has permanently failed
    case failed(Error)
}

extension TransportState: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .failed(let error): return "failed: \(error)"
        }
    }

    public var debugDescription: String {
        switch self {
        case .disconnected: return "Transport is disconnected"
        case .connecting: return "Transport is connecting"
        case .connected: return "Transport is connected"
        case .failed(let error): return "Transport has failed: \(error)"
        }
    }
}

extension TransportState: Equatable {
    public static func == (lhs: TransportState, rhs: TransportState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
            (.connecting, .connecting),
            (.connected, .connected),
            (.failed, .failed):
            return true
        default:
            return false
        }
    }

}

/// Protocol providing retry capability to transports
public protocol RetryableTransport: MCPTransport {
    /// Perform operation with retry
    func withRetry<T>(
        operation: String,
        block: @escaping () async throws -> T
    ) async throws -> T
}

extension RetryableTransport {
    public func withRetry<T>(
        operation: String,
        block: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 1
        var lastError: Error?

        while attempt <= configuration.retryPolicy.maxAttempts {
            do {
                return try await block()
            } catch {
                lastError = error

                // Don't retry if we've hit max attempts
                guard attempt < configuration.retryPolicy.maxAttempts else {
                    break
                }

                // Calculate delay for next attempt
                let delay = configuration.retryPolicy.delay(forAttempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                attempt += 1
            }
        }

        throw TransportError.operationFailed(lastError!)
    }
}
