//
//  SecureLogger.swift
//  SecureContainer
//
//  Created by Assistant on 21/4/2026.
//

import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// This type protects all mutable state via its private serial DispatchQueue (`queue`).
/// We therefore declare it @unchecked Sendable to allow capturing `self` in @Sendable closures used by GCD.
public final actor SecureLogger
{
	/// Specifies configuration options for `SecureLogger`.
	public struct Configuration: Sendable
	{
		/// The separator to use between columns of text. Defaults to TAB character.
		public let columnSeparator: String
		
        /// Maximum number of messages to buffer before forcing a flush. Defaults to 32.
        public let maxBufferCount: Int
		
        /// Maximum total byte size of buffered messages (approximate, UTF-8) before forcing a flush. Defaults to 4kB.
        public let maxBufferBytes: Int
		
        /// Time interval to flush buffered messages if not flushed by size thresholds. Defaults to 2 seconds.
        public let flushInterval: TimeInterval

		public init(columnSeparator: String = "\t",
					maxBufferCount: Int = 64,
                    maxBufferBytes: Int = 8192,
                    flushInterval: TimeInterval = 2.0)
		{
			self.columnSeparator = columnSeparator
            self.maxBufferCount = maxBufferCount
            self.maxBufferBytes = maxBufferBytes
            self.flushInterval = flushInterval
        }
    }

	private var flushTask: Task<Void, Never>? = nil
    private var buffer: [String] = []
    private var bufferedBytes: Int = 0
    private var isShuttingDown = false
	
	public let secureFile: SecureFile
	public let configuration: Configuration
	
	public private(set) var lastLine: String = ""
	
	/// Initialises a secure logger using an existing `SecureFile` instance.
	/// - Parameters:
	///   - secureFile: A `SecureFile` to write to.
	///   - configuration: The logging and buffer configuration.
	public init(secureFile: SecureFile,
				configuration: Configuration = Configuration())
	{
		self.configuration = configuration
		self.secureFile = secureFile
		Task {
			await startFlushInterval()
			await registerLifecycleObserversIfNeeded()
		}
	}
	
	/// Initialises a secure logger using a `URL`, `SymmetricKey` and other configuration options.
	/// - Parameters:
	///   - url: The `URL` for the log file.
	///   - key: A `SymmetricKey` used to encrypt the log file's contents.
	///   - encryptionMethod: The `EncryptionMethod` to use for the `SecureFile`. Defaults to `.best`.
	///   - temporaryDirectory: The temporary directory to use for atomic writes. Defaults to `FileManager.default.temporaryDirectory`.
	///   - configuration: The logger configuration.
	public init(url: URL,
				key: SymmetricKey,
				encryptionMethod: EncryptionMethod = .best,
				temporaryDirectory: URL? = nil,
				configuration: Configuration = Configuration())
	{
		let secureFile = SecureFile(url: url, key: key, encryptionMethod: encryptionMethod, temporaryDirectory: temporaryDirectory)
		self.init(secureFile: secureFile, configuration: configuration)
	}

    deinit // nonisolated shutdown
	{
		isShuttingDown = true
		flushTask?.cancel()
		
		let observers = lifecycleObservers
		Task {
			await observers?.remove()
		}
		
		let buffer = buffer
		guard !buffer.isEmpty else
		{
			return
		}
		
		let secureFile = secureFile
		
		Task { [secureFile, buffer] in
			try await Self.append(newLines: buffer, to: secureFile)
		}
    }
	
	/// Determines if the log has entries that need to be flushed (`true`) or if the buffer is empty (`false`).
	public var needsFlushing: Bool
	{
		get
		{
			!buffer.isEmpty
		}
	}
	
	/// Add an INFO message to the log along with an ISO-8601 timestamp and log entry type indicator to be flushed later.
	/// - Parameters:
	///   - type: The log entry type.
	///   - message: The log message to be written.
	///   - additionalData: An array of additional string data to append as columns.
	///   - now: The date and time of the message. This defaults to now.
	@discardableResult
	public func notice(_ message: String, additionalData: [String] = [], now: Date? = nil) -> String
	{
		return log(type: .notice, message, additionalData: additionalData, now: now)
	}
	
	/// Add an INFO message to the log along with an ISO-8601 timestamp and log entry type indicator to be flushed later.
	/// - Parameters:
	///   - type: The log entry type.
	///   - message: The log message to be written.
	///   - additionalData: An array of additional string data to append as columns.
	///   - now: The date and time of the message. This defaults to now.
	@discardableResult
	public func info(_ message: String, additionalData: [String] = [], now: Date? = nil) -> String
	{
		return log(type: .info, message, additionalData: additionalData, now: now)
	}
	
	/// Add a WARNING message to the log along with an ISO-8601 timestamp and log entry type indicator to be flushed later.
	/// - Parameters:
	///   - type: The log entry type.
	///   - message: The log message to be written.
	///   - additionalData: An array of additional string data to append as columns.
	///   - now: The date and time of the message. This defaults to now.
	@discardableResult
	public func warning(_ message: String, additionalData: [String] = [], now: Date? = nil) -> String
	{
		return log(type: .warning, message, additionalData: additionalData, now: now)
	}
	
	/// Add an ERROR message to the log along with an ISO-8601 timestamp and log entry type indicator to be flushed later.
	/// - Parameters:
	///   - type: The log entry type.
	///   - message: The log message to be written.
	///   - additionalData: An array of additional string data to append as columns.
	///   - now: The date and time of the message. This defaults to now.
	@discardableResult
	public func error(_ message: String, additionalData: [String] = [], now: Date? = nil) -> String
	{
		return log(type: .error, message, additionalData: additionalData, now: now)
	}
	
	/// Add a PERF message to the log along with an ISO-8601 timestamp and log entry type indicator to be flushed later.
	/// - Parameters:
	///   - type: The log entry type.
	///   - message: The log message to be written.
	///   - now: The date and time of the message. This defaults to now.
	@discardableResult
	public func performance(_ message: String, additionalData: [String] = [], now: Date? = nil) -> String
	{
		return log(type: .performance, message, additionalData: additionalData, now: now)
	}
	
	/// Add a message to the log along with an ISO-8601 timestamp and log entry type indicator to be flushed later.
	/// Additional columns of string data can be appended as well.
	/// - Parameters:
	///   - type: The log entry type.
	///   - message: The log message to be written.
	///   - additionalData: An array of additional string data to append as columns.
	///   - now: The date and time of the message. This defaults to now.
	@discardableResult
	public func log(type: LogType, _ message: String, additionalData: [String] = [], now: Date? = nil) -> String
	{
		let parts = [
			ISO8601DateFormatter().string(from: now ?? Date()),
			type.rawValue,
			message
		] + additionalData
		
		let line = parts.joined(separator: self.configuration.columnSeparator).trimmingCharacters(in: .newlines)
		log(line: line)
		return line
	}
	
	/// Adds a pre-formatted line to the log buffer to be flushed later.
	/// - Parameter line: The pre-formatted line to be written to the log. A new line character will be added automatically.
	public func log(line: String) -> Void
	{
		let line = line.trimmingCharacters(in: .newlines) + "\n"
		
		guard !self.isShuttingDown else
		{
			return
		}
		
		self.buffer.append(line)
		self.bufferedBytes += line.lengthOfBytes(using: .utf8)
		
		if self.buffer.count >= self.configuration.maxBufferCount || self.bufferedBytes >= self.configuration.maxBufferBytes
		{
			Task {
				await self.flush()
			}
		}
    }
	
	/// Flushes the log buffer.
	public func flush() async -> Void
	{
		guard !buffer.isEmpty else
		{
			return
		}
		
		self.stopFlushInterval()
		
		let lines = buffer
		buffer.removeAll(keepingCapacity: true)
		bufferedBytes = 0
		
		defer {
			self.startFlushInterval()
		}
		
		do
		{
			try await Self.append(newLines: lines, to: secureFile)
		}
		catch
		{
			// On failure, requeue the lines for a later attempt (best-effort)
			buffer.insert(contentsOf: lines, at: 0)
			bufferedBytes = buffer.reduce(0) { $0 + $1.lengthOfBytes(using: .utf8) + 1 }
		}
    }

    private func startFlushInterval()
	{
        guard configuration.flushInterval > 0,
			  flushTask == nil else
		{
			return
		}
		
		flushTask = Task { [weak self] in
			while !Task.isCancelled
			{
				guard let interval = self?.configuration.flushInterval else
				{
					return
				}
				
				try? await Task.sleep(for: .microseconds(interval * 1_000_000))
				
				guard let self = self else
				{
					return
				}
				
				await self.flush()
			}
		}
    }

    private func stopFlushInterval()
	{
		flushTask?.cancel()
		flushTask = nil
    }
	
	@discardableResult
	private static func append(newLines: [String], to secureFile: SecureFile) async throws -> UInt64
	{
		let exists = await secureFile.exists
		var existing = exists ? try await secureFile.readAsString() : ""
		existing += newLines.joined()
		return try await secureFile.write(string: existing)
	}

	@MainActor
	private struct LifecycleObservers: Sendable
	{
		#if canImport(UIKit)
		let willResignActiveObserver: NSObjectProtocol
		let willTerminateObserver: NSObjectProtocol
		#endif
		
		func remove() -> Void
		{
			#if canImport(UIKit)
			NotificationCenter.default.removeObserver(willResignActiveObserver)
			NotificationCenter.default.removeObserver(willTerminateObserver)
			#endif
		}
	}
	
	private var lifecycleObservers: LifecycleObservers? = nil

    private func registerLifecycleObserversIfNeeded() async
	{
        #if canImport(UIKit)
        let willResign = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
			Task {
				await self?.flush()
			}
        }
        
		let willTerminate = NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
			Task {
				await self?.flush()
			}
        }
		
		lifecycleObservers = await LifecycleObservers(willResignActiveObserver: willResign, willTerminateObserver: willTerminate)
        #endif
    }

    private func unregisterLifecycleObserversIfNeeded() async
	{
        #if canImport(UIKit)
		await lifecycleObservers?.remove()
		lifecycleObservers = nil
        #endif
    }
}

