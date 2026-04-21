//
//  SecureFile.swift
//  SecureContainer
//
//  Created by Nick Bedford on 15/4/2026.
//

import Foundation
import CryptoKit

/// `SecureFile` is the interface to read and write secured files using encryption,
/// such as AES-GCM encryption with a symmetric key. Apple's CryptoKit framework is used.
public class SecureFile
{
	private static let tempFilePrefix = "TempSecureFile_"
	private static let magicHeader = "SECFILE_"
	private static let magicHeaderData = magicHeader.data(using: .ascii)!
	private static let maxExpectedContentLength = 1024 * 1024 * 1024
	
	public let url: URL
	public let encryptionMethod: EncryptionMethod
	
	private let key: SymmetricKey
	private let temporaryDirectory: URL
	
	
	/// Initialises a `SecureFile` interface to a file at a specified URL. This file
	/// does not need to exist yet.
	/// - Parameters:
	///   - url: The URL where the file exists or is to be written to.
	///   - key: A `SymmetricKey` usable by the `SecureFileFormat` encryption method.
	///   - format: The format to use 
	///   - temporaryDirectory: Optional. The temporary directory to use when writing the file atomically.
	///   This will use `FileManager.default.temporaryDirectory` if not specified.
	public init(url: URL,
				key: SymmetricKey,
				encryptionMethod: EncryptionMethod = .best,
				temporaryDirectory: URL? = nil)
	{
		self.url = url
		self.key = key
		self.encryptionMethod = encryptionMethod
		self.temporaryDirectory = temporaryDirectory ?? FileManager.default.temporaryDirectory
	}
	
	/// Determines whether the file exists or not.
	public var exists: Bool
	{
		get
		{
			FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
		}
	}
	
	/// Reads the file into its original plain-text binary data.
	/// - Returns: A Data object containing the original plain-text data.
	public func read() throws -> Data
	{
		guard exists else
		{
			throw SecureFileError.fileMissing(url)
		}
		
		let fileHandle = try FileHandle(forReadingFrom: url)
		
		defer {
			try? fileHandle.close()
		}
		
		let magicHeaderData = try fileHandle.read(expectedCount: Self.magicHeaderData.count)
		guard String(data: magicHeaderData, encoding: .ascii) == Self.magicHeader else
		{
			throw SecureFileError.invalidHeader(url)
		}
		
		let encryptionMethodValue = try fileHandle.readInt8()
		guard let encryptionMethod = EncryptionMethod(rawValue: encryptionMethodValue) else
		{
			throw SecureFileError.invalidFormat(url)
		}
		
		let version = try fileHandle.readInt8()
		guard encryptionMethod.versions.contains(version) else
		{
			throw SecureFileError.invalidVersion(url)
		}
		
		switch encryptionMethod
		{
			case .aesGcm:
				return try readAesGcm(fileHandle, version: version)
		}
	}
	
	/// Reads the file into its original plain-text data and return it as
	/// a UTF-8 string.
	/// - Returns: A String containing the original plain-text data decoded as UTF-8.
	public func readAsString() throws -> String
	{
		guard let string = String(data: try read(), encoding: .utf8) else
		{
			throw SecureFileError.invalidStringConverson(url)
		}
		
		return string
	}
	
	/// Reads the file as JSON and decode it into its original type.
	/// - Parameter type: The `Decodable` type to decode into.
	/// - Returns: An object of the specified `Decodable` type.
	public func readJson<T: Decodable>(as type: T.Type) throws -> T
	{
		try JSONDecoder().decode(type, from: try read())
	}
	
	/// Writes a string encoded in UTF-8 to the file securely using the specified `encryptionMethod`.
	/// - Parameter string: The UTF-8 string to write.
	public func write(string: String) throws -> Void
	{
		guard let data = string.data(using: .utf8) else
		{
			throw SecureFileError.invalidStringConverson(url)
		}
		
		try write(data)
	}
	
	/// Writes a JSON-encoded `Encodable` object to the file securely using the specified `encryptionMethod`.
	/// - Parameter jsonEncodable: The JSON-encodable `Encodable` object to write to the file.
	public func write(jsonEncodable: Encodable) throws -> Void
	{
		let encoded = try JSONEncoder().encode(jsonEncodable)
		try write(encoded)
	}
	
	/// Writes a binary `Data` object to the file securely using the specified `encryptionMethod`.
	/// - Parameter data: The `Data` object to write.
	public func write(_ data: Data) throws -> Void
	{
		let basename = "\(Self.tempFilePrefix)\(randomString()).tmp"
		let temporaryUrl = temporaryDirectory.appending(component: basename, directoryHint: .notDirectory)
		
		guard FileManager.default.createFile(atPath: temporaryUrl.path(), contents: nil) else
		{
			throw SecureFileError.fileCreationError(temporaryUrl)
		}
		
		do
		{
			let success = try lock(urlForWriting: temporaryUrl) { fileHandle in
				try fileHandle.write(contentsOf: Self.magicHeaderData)
				try fileHandle.write(encryptionMethod.rawValue)
				try fileHandle.write(encryptionMethod.currentVersion)
				
				switch encryptionMethod
				{
					case .aesGcm:
						try writeAesGcm(data: data, to: fileHandle)
				}
			}
			
			guard success else
			{
				throw SecureFileError.fileLocked(temporaryUrl)
			}
		}
		catch
		{
			remove(urlIfExists: temporaryUrl)
			throw error
		}
		
		///
		/// If an encrypted file from a previous save already exists,
		/// back it up to another file first.
		///
		
		let urlForBackupOfPrevious = exists ?
			url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).backup.\(Int.random(in: 100_000_000...999_999_999))") : nil
		
		if let urlForBackupOfPrevious = urlForBackupOfPrevious
		{
			remove(urlIfExists: urlForBackupOfPrevious)
			
			do
			{
				try FileManager.default.moveItem(at: url, to: urlForBackupOfPrevious)
			}
			catch
			{
				remove(urlIfExists: temporaryUrl)
				throw error
			}
		}
		
		do
		{
			///
			/// Move the new encrypted file into place then delete the backup of the previous version
			///
			
			try FileManager.default.moveItem(at: temporaryUrl, to: url)
			remove(urlIfExists: urlForBackupOfPrevious)
		}
		catch
		{
			///
			/// Otherwise, move the backed up copy back into place and delete the temporary file
			///
			
			if let urlForBackupOfPrevious = urlForBackupOfPrevious
			{
				try FileManager.default.moveItem(at: urlForBackupOfPrevious, to: url)
			}
			
			remove(urlIfExists: temporaryUrl)
			throw error
		}
	}
	
	private func readNonce(from fileHandle: FileHandle, countBytes count: Int) throws -> Data
	{
		guard let iv = try fileHandle.read(upToCount: count),
			  iv.count == count else
		{
			throw SecureFileError.invalidNonce(url)
		}
		
		return iv
	}
	
	private func readAesGcm(_ fileHandle: FileHandle, version: Int8) throws -> Data
	{
		// Only one version (pre-validated), no need to check `version`
		
		let nonce = try AES.GCM.Nonce(data: readNonce(from: fileHandle, countBytes: EncryptionMethod.aesGcm.nonceLength))
		
		let ciphertextLength = try fileHandle.readInt(max: Self.maxExpectedContentLength)
		let ciphertext = try fileHandle.read(expectedCount: ciphertextLength)
		
		let authenticationTagLength = try fileHandle.readInt(max: 16, min: 16)
		let authenticationTag = try fileHandle.read(expectedCount: authenticationTagLength)
		
		let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: authenticationTag)
		
		return try AES.GCM.open(sealedBox, using: key)
	}
	
	private func writeAesGcm(data: Data, to fileHandle: FileHandle) throws -> Void
	{
		let nonce = AES.GCM.Nonce()
		
		try nonce.withUnsafeBytes { bytes in
			try fileHandle.write(contentsOf: bytes)
		}
		
		let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
		
		try fileHandle.write(sealedBox.ciphertext.count)
		try fileHandle.write(contentsOf: sealedBox.ciphertext)
		
		try fileHandle.write(sealedBox.tag.count)
		try fileHandle.write(contentsOf: sealedBox.tag)
	}
}
