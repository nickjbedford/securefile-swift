//
//  FileHandle.swift
//  iOrthoticsScanner
//
//  Created by Nick Bedford on 10/8/21.
//  Copyright © 2021 iOrthotics Pty Ltd. All rights reserved.
//

import Foundation

public extension FileHandle
{
	func read(expectedCount count: Int) throws -> Data
	{
		guard let data = try read(upToCount: count),
			  data.count == count else
		{
			throw SecureFileError.dataReadError
		}
		
		return data
	}
	
	func readInt8() throws -> Int8
	{
		guard let byte = try read(expectedCount: 1).first else
		{
			throw SecureFileError.dataReadError
		}
		
		return Int8(bitPattern: byte)
	}
	
	func readInt(max: Int? = nil, min: Int? = 0) throws -> Int
	{
		let intSize = MemoryLayout<Int64>.size
		
		guard let data = try read(upToCount: intSize),
			  data.count == intSize else
		{
			throw SecureFileError.dataReadError
		}
		
		guard let value = Int(exactly: Int64(bigEndian: data.withUnsafeBytes {
			$0.load(as: Int64.self)
		})) else
		{
			throw SecureFileError.integerError
		}
		
		guard value >= (min ?? Int.min) && value <= (max ?? Int.max) else
		{
			throw SecureFileError.integerOverflowError
		}
		
		return value
	}
	
	func write(_ value: Int) throws -> Void
	{
		var value = Int64(value).bigEndian
		let data = Data(bytes: &value, count: MemoryLayout<Int64>.size)
		try write(contentsOf: data)
	}
	
	func write(_ value: Int8) throws -> Void
	{
		try write(contentsOf: Data([UInt8(bitPattern: value)]))
	}
}
