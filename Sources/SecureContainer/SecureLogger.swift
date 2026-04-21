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

/// SecureLogger buffers pre-formatted messages and persists them to an encrypted log file
/// using `SecureFile`. It batches appends for efficiency and uses atomic writes for safety.
public final class SecureLogger
{
    public struct Configuration
	{
		/// The separator to use between columns of text. Defaults to TAB character.
		public let columnSeparator: String
		
        /// Maximum number of messages to buffer before forcing a flush
        public let maxBufferCount: Int
		
        /// Maximum total byte size of buffered messages (approximate, UTF-8) before forcing a flush
        public let maxBufferBytes: Int
		
        /// Time interval to flush buffered messages if not flushed by size thresholds. Defaults to 2 seconds.
        public let flushInterval: TimeInterval

		public init(columnSeparator: String = "\t",
					maxBufferCount: Int = 64,
                    maxBufferBytes: Int = 4096,
                    flushInterval: TimeInterval = 2.0)
		{
			self.columnSeparator = columnSeparator
            self.maxBufferCount = maxBufferCount
            self.maxBufferBytes = maxBufferBytes
            self.flushInterval = flushInterval
        }
    }

    private let queue: DispatchQueue
    public let secureFile: SecureFile
    private var buffer: [String] = []
    private var bufferedBytes: Int = 0
    private var timer: DispatchSourceTimer?
    private var isShuttingDown = false
	
	public init(url: URL,
				secureFile: SecureFile,
				configuration: Configuration = Configuration())
	{
		self.configuration = configuration
		self.secureFile = secureFile
		self.queue = DispatchQueue(label: "SecureLogger.queue", qos: .utility)
		startTimer()
		registerLifecycleObserversIfNeeded()
	}
	
	public convenience init(url: URL,
							key: SymmetricKey,
							encryptionMethod: EncryptionMethod = .best,
							temporaryDirectory: URL? = nil,
							configuration: Configuration = Configuration())
	{
		let secureFile = SecureFile(url: url, key: key, encryptionMethod: encryptionMethod, temporaryDirectory: temporaryDirectory)
		self.init(url: url, secureFile: secureFile, configuration: configuration)
	}

    public let configuration: Configuration

    deinit
	{
        shutdown()
    }
	
	/// Determines if the log has been flushed (`true`) or if there are still lines in the buffer (`false`).
	public var needsFlushing: Bool
	{
		get
		{
			queue.sync {
				!buffer.isEmpty
			}
		}
	}
	
	/// Add a message to the log along with an ISO-8601 timestamp and log entry type indicator to be flushed later.
	/// - Parameters:
	///   - type: The log entry type.
	///   - message: The log message to be written.
	///   - now: The date and time of the message. This defaults to now.
	public func log(type: LogType, _ message: String, now: Date? = nil) -> Void
	{
		let line = [
			ISO8601DateFormatter().string(from: now ?? Date()),
			type.rawValue,
			message
		].joined(separator: configuration.columnSeparator)
		
		log(line: line)
	}
	
	/// Adds a pre-formatted line to the log buffer to be flushed later.
	/// - Parameter line: The pre-formatted line to be written to the log. A new line character will be added automatically.
	public func log(line: String) -> Void
	{
		let line = line.trimmingCharacters(in: .newlines) + "\n"
		
        queue.async { [weak self] in
            guard let self = self,
				  !self.isShuttingDown else
			{
				return
			}
			
            self.buffer.append(line)
            self.bufferedBytes += line.lengthOfBytes(using: .utf8)
			
            if self.buffer.count >= self.configuration.maxBufferCount || self.bufferedBytes >= self.configuration.maxBufferBytes
			{
                self.flushLocked()
            }
        }
    }

    public func flush()
	{
        queue.async { [weak self] in
            self?.flushLocked()
        }
    }

    public func shutdown()
	{
        queue.sync {
            isShuttingDown = true
            stopTimer()
            flushLocked()
            unregisterLifecycleObserversIfNeeded()
        }
    }

    private func startTimer()
	{
        guard configuration.flushInterval > 0,
			  timer == nil else
		{
			return
		}
		
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + configuration.flushInterval, repeating: configuration.flushInterval)
        timer.setEventHandler { [weak self] in
			#if DEBUG
			if !(self?.buffer.isEmpty ?? true)
			{
				print("[SecureLogger]: Flushing after timeout...")
			}
			#endif
			
            self?.flushLocked()
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer()
	{
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func flushLocked()
	{
        guard !buffer.isEmpty else
		{
			return
		}
		
		#if DEBUG
		print("[SecureLogger]: Flushing \(buffer.count) new lines to log file...")
		#endif
		
        let lines = buffer
        buffer.removeAll(keepingCapacity: true)
        bufferedBytes = 0

        do
		{
			let start = DispatchTime.now()
			
			var existing = secureFile.exists ? try secureFile.readAsString() : ""
			existing += lines.joined()
			
			try secureFile.write(string: existing)
			
			let duration = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
			print("[SecureLogger]: Flush \(existing.count) characters took \(duration)ms")
        }
		catch
		{
            // On failure, requeue the lines for a later attempt (best-effort)
            buffer.insert(contentsOf: lines, at: 0)
            bufferedBytes = buffer.reduce(0) { $0 + $1.lengthOfBytes(using: .utf8) + 1 }
			
			print("[SecureLogger]: Flushing failed, requeuing due to error '\(error.localizedDescription)'.")
        }
    }

    #if canImport(UIKit)
    private var willResignActiveObserver: NSObjectProtocol?
    private var willTerminateObserver: NSObjectProtocol?
    #endif

    private func registerLifecycleObserversIfNeeded()
	{
        #if canImport(UIKit)
        let center = NotificationCenter.default
		
        willResignActiveObserver = center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.flush()
        }
        
		willTerminateObserver = center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.shutdown()
        }
        #endif
    }

    private func unregisterLifecycleObserversIfNeeded()
	{
        #if canImport(UIKit)
        let center = NotificationCenter.default
        if let o = willResignActiveObserver
		{
			center.removeObserver(o)
		}
		
        if let o = willTerminateObserver
		{
			center.removeObserver(o)
		}
		
        willResignActiveObserver = nil
        willTerminateObserver = nil
        #endif
    }
}
