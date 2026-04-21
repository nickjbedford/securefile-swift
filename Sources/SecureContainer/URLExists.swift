//
//  URLExists.swift
//  SecureFile
//
//  Created by Nick Bedford on 17/4/2026.
//

import Foundation

public struct URLExists: Sendable
{
	public let exists: Bool
	public let isDirectory: Bool
	
	public init(url: URL)
	{
		var isDirectory: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
		self.init(exists: exists, isDirectory: isDirectory.boolValue)
	}
	
	public init(exists: Bool, isDirectory: Bool)
	{
		self.exists = exists
		self.isDirectory = exists && isDirectory
	}
}
