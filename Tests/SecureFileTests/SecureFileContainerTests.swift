import Testing
import CryptoKit
import Foundation

@testable import SecureFile

@Test func secureContainerCanCreateSecureFile() async throws
{
	let key = SymmetricKey(size: .bits256)
	let directory = try testDirectory().appending(component: "MyContainer_\(randomString())")
	let container = try SecureFileContainer(directory: directory, key: key)
	
	var isDirectory: ObjCBool = false
	let containerExists = FileManager.default.fileExists(atPath: container.directory.path(percentEncoded: false), isDirectory: &isDirectory)
	#expect(containerExists && isDirectory.boolValue)
	
	let file = container.file("Test.txt")
	
	#expect(await !file.exists)
	
	try await file.write(string: "Hello, world!")
	
	#expect(await file.exists)
	#expect(try await file.readAsString() == "Hello, world!")
}

@Test func nestedSecureContainerCanCreateSecureFile() async throws
{
	let key = SymmetricKey(size: .bits256)
	let directory = try testDirectory().appending(component: "MyContainer_\(randomString())")
	let container = try SecureFileContainer(directory: directory, key: key).folder("Nested")
	
	let file = container.file("Test.txt")
	
	#expect(await !file.exists)
	
	try await file.write(string: "Hello, world!")
	
	#expect(await file.exists)
	#expect(try await file.readAsString() == "Hello, world!")
}
