import Testing
import CryptoKit
import Foundation

@testable import SecureFile

final class EncodableTest: Codable
{
	public let number: Int
	public let string: String
	public let data: Data
	
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
	
	#expect(await !file.exists)

	let encodable = EncodableTest(number: 123, string: "Hello, world!", data: "Goodbye, universe!".data(using: .utf8)!)
	let bytes = try await file.write(jsonEncodable: encodable)
	
	#expect(bytes > 0)
	#expect(await file.exists)
	
	let decoded = try await file.readJson(as: EncodableTest.self)
	
	#expect(decoded.number == encodable.number)
	#expect(decoded.string == encodable.string)
	#expect(String(data: decoded.data, encoding: .utf8) == "Goodbye, universe!")
	
	await #expect(throws: CryptoKitError.self) {
		let otherKey = SymmetricKey(size: .bits256)
		let incorrectFile = SecureFile(url: url, key: otherKey)
		
		#expect(await incorrectFile.exists)
		
		let _ = try await incorrectFile.readJson(as: EncodableTest.self)
	}
}
