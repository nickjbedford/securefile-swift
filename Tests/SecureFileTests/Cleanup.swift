//
//  Cleanup.swift
//  SecureFile
//
//  Created by Nick Bedford on 15/4/2026.
//

import Foundation

func testDirectory() throws -> URL
{
	let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(component: "Testing")
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	return directory
}

func cleanup(directory: URL? = nil, removeSelf: Bool = false) -> Void
{
	guard let directory = directory else
	{
		if let directory = try? testDirectory()
		{
			cleanup(directory: directory)
		}
		return
	}
	
	guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else
	{
		return
	}
	
	for case let url as URL in enumerator
	{
		try? FileManager.default.removeItem(at: url)
	}
	
	if removeSelf
	{
		try? FileManager.default.removeItem(at: directory)
	}
}

