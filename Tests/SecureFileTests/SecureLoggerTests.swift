import Testing
import CryptoKit
import Foundation

@testable import SecureFile

@Test func secureLoggerLogsMessagesAsynchronously() async throws
{
	let url = FileManager.default.temporaryDirectory.appending(component: "secure_log_\(randomString()).txt")
	let key = SymmetricKey(size: .bits256)
	let log = SecureLogger(url: url, key: key)
	
	#expect(await !log.secureFile.exists)
	
    let separator = await log.configuration.columnSeparator

    let now1 = Date().addingTimeInterval(-2)
    let now2 = now1.addingTimeInterval(2)

    let expected1 = [
        ISO8601DateFormatter().string(from: now1),
        LogType.info.rawValue,
        "Hello, world!"
    ].joined(separator: separator)

    let expected2 = [
        ISO8601DateFormatter().string(from: now2),
        LogType.error.rawValue,
        "Goodbye, world!"
    ].joined(separator: separator)

    #expect(await !log.needsFlushing)

    await log.log(type: .info, "Hello, world!", now: now1)
	await log.log(type: .error, "Goodbye, world!", now: now2)

    #expect(await log.needsFlushing)

    print("[TEST] Sleeping...")

	try await Task.sleep(for: .seconds(log.configuration.flushInterval + 0.5))

    print("[TEST] Sleep complete")
    #expect(await !log.needsFlushing)

	let contents = try await log.secureFile.readAsString()
	let lines = contents.split(separator: "\n")
	#expect(lines[0] == expected1)
	#expect(lines[1] == expected2)
	
	await log.flush()
}
