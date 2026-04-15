//
//  Helpers.swift
//  SecureFile
//
//  Created by Nick Bedford on 15/4/2026.
//

import Foundation

public func remove(urlIfExists url: URL?) -> Void
{
	guard let path = url?.path(),
		  FileManager.default.fileExists(atPath: path) else
	{
		return
	}
	
	try? FileManager.default.removeItem(atPath: path)
}

public func randomString(length: Int = 12) -> String
{
	let chars = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
	return String((0..<length).map { _ in
		chars.randomElement()!
	})
}

public func lock(urlForWriting url: URL, timeout: TimeInterval = 5, _ closure: (FileHandle) throws -> Void) throws -> Bool
{
	let fileHandle = try FileHandle(forWritingTo: url)
	let fileDescriptor = fileHandle.fileDescriptor
	let start = Date()
	var locked = false
	
	defer {
		if locked
		{
			flock(fileDescriptor, LOCK_UN)
		}
		try? fileHandle.close()
	}
	
	while Date().timeIntervalSince(start) < timeout
	{
		if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0
		{
			locked = true
			break
		}
		
		let err = errno
		guard err == EWOULDBLOCK else
		{
			return false
		}
		
		usleep(10_000)
	}
	
	guard locked else
	{
		return false
	}
	
	try closure(fileHandle)
	return true
}

func print(_ label: String, hex bytes: [UInt8]) -> Void
{
	let hex = bytes.map { String(format: "%02x", $0) }.joined()
	print("\(label): \(hex)")
}

func print(_ label: String, hex data: Data) -> Void
{
	data.withUnsafeBytes { bytes in
		print(label, hex: [UInt8](bytes))
	}
}
