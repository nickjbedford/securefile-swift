//
//  FileHandle.swift
//  iOrthoticsScanner
//
//  Created by Nick Bedford on 10/8/21.
//  Copyright © 2021 iOrthotics Pty Ltd. All rights reserved.
//

import Foundation

extension FileHandle
{
	func read(expectedCount count: Int) throws -> Data
	{
		guard let data = try read(upToCount: count) else
		{
			throw NSError(domain: "com.iorthotics.scanner", code: 0, userInfo: [
				NSLocalizedDescriptionKey: "File data could not be read"
			])
		}
		
		guard data.count == count else
		{
			throw NSError(domain: "com.iorthotics.scanner", code: 0, userInfo: [
				NSLocalizedDescriptionKey: "File data did not match expected length"
			])
		}
		
		return data
	}
	
	func readDataCount(expectedMax max: Int? = nil) throws -> Int
	{
		guard let data = try read(upToCount: MemoryLayout<UInt64>.size),
			  data.count == MemoryLayout<UInt64>.size,
			  let unsigned = data.bigEndianToUInt64 else
		{
			throw NSError(domain: "com.iorthotics.scanner", code: 0, userInfo: [
				NSLocalizedDescriptionKey: "Count value not found in file"
			])
		}
		
		guard let count = Int(exactly: unsigned) else
		{
			throw NSError(domain: "com.iorthotics.scanner", code: 0, userInfo: [
				NSLocalizedDescriptionKey: "Count value is not valid"
			])
		}
		
		guard count >= 0 && count <= (max ?? Int.max) else
		{
			throw NSError(domain: "com.iorthotics.scanner", code: 0, userInfo: [
				NSLocalizedDescriptionKey: "Count is not within the expected range"
			])
		}
		
		return count
	}
	
	func write(dataCount count: Int) throws -> Void
	{
		guard let value = UInt64(exactly: count) else
		{
			throw NSError(domain: "com.iorthotics.scanner", code: 0, userInfo: [
				NSLocalizedDescriptionKey: "Could not write data length to file handle"
			])
		}
			
		try write(contentsOf: value.bigEndianData)
	}
}
