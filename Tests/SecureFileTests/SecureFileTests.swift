import Testing
import CryptoKit
import Foundation

@testable import SecureFile

class EncodableTest: Codable
{
	public var number: Int
	public var string: String
	public var data: Data
	
	init(number: Int, string: String, data: Data)
	{
		self.number = number
		self.string = string
		self.data = data
	}
}

@Test func encodableIsWrittenThenReadSuccessfullyUntilKeyIsIncorrect() async throws
{
	let url = FileManager.default.temporaryDirectory.appending(component: "hello_world_\(randomString()).txt")
	let key = SymmetricKey(size: .bits256)
	let file = SecureFile(url: url, key: key)
	
	#expect(!file.exists)

	let encodable = EncodableTest(number: 123, string: "Hello, world!", data: "Goodbye, universe!".data(using: .utf8)!)
	try file.write(jsonEncodable: encodable)
	
	#expect(file.exists)
	
	let decoded = try file.readJson(as: EncodableTest.self)
	
	#expect(decoded.number == encodable.number)
	#expect(decoded.string == encodable.string)
	#expect(String(data: decoded.data, encoding: .utf8) == "Goodbye, universe!")
	
	#expect(throws: CryptoKitError.self) {
		let otherKey = SymmetricKey(size: .bits256)
		let incorrectFile = SecureFile(url: url, key: otherKey)
		
		#expect(incorrectFile.exists)
		
		let _ = try incorrectFile.readJson(as: EncodableTest.self)
	}
}
