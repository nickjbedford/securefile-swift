//
//  SecureFileContainer.swift
//  iO Scanner
//
//  Created by Nick Bedford on 15/4/2026.
//

import Foundation
import CryptoKit

/// `SecureFileContainer` is the interface to read and write secure encrypted files under a container directory.
/// It allows easy creation of nested container folders and access to named files, all using a single `SymmetricKey`.
public class SecureFileContainer
{
	public let directory: URL
	private let key: SymmetricKey
	private let temporaryDirectory: URL
	
	/// Initialises a secure file container pointing to the directory specified. This initialiser will also ensure the directory exists.
	/// - Parameters:
	///   - directory: The directory where files will be encrypted using `SecureFile`.
	///   - key: The symmetric key to use.
	///   - temporaryDirectory: Optional. The temporary file directory to pass to `SecureFile` instances for use when writing encrypted files.
	public init(directory: URL,
		 key: SymmetricKey,
		 temporaryDirectory: URL? = nil) throws
	{
		self.directory = directory
		self.key = key
		self.temporaryDirectory = temporaryDirectory ?? FileManager.default.temporaryDirectory
		try ensureExists()
	}
	
	/// Creates a `SecureFile` instance pointing to a file path in this container directory. The file
	/// does not need to exist yet.
	/// - Parameter name: The basename of the file.
	/// - Returns: A `SecureFile` instance pointing to the file path specified.
	public func file(_ basename: String) -> SecureFile
	{
		let url = directory.appending(component: basename, directoryHint: .notDirectory)
		return SecureFile(url: url, key: key, temporaryDirectory: temporaryDirectory)
	}
	
	/// Creates a `SecureFileContainer` instance to a folder under this directory and ensures it is created on disk.
	/// - Parameter name: The name of the sub-folder.
	/// - Returns: A `SecureFileContainer` instance pointing to the
	public func folder(_ name: String) throws -> SecureFileContainer
	{
		let directory = self.directory.appending(component: name, directoryHint: .isDirectory)
		return try SecureFileContainer(directory: directory, key: key)
	}
	
	/// Determines if the folder under this container exists and is a directory.
	/// - Parameter name: The name of the sub-folder.
	/// - Returns: Whether the sub-folder exists and is a directory.
	public func hasFolder(_ name: String) -> Bool
	{
		let directory = self.directory.appending(component: name, directoryHint: .isDirectory)
		var isDirectory: ObjCBool = false
		
		guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false), isDirectory: &isDirectory) else
		{
			return false
		}
		
		return isDirectory.boolValue
	}
	
	private func ensureExists() throws -> Void
	{
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		
		guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else
		{
			throw SecureFileContainerError.directoryNotCreated
		}
	}
}
