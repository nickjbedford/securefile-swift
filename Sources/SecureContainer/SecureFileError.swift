//
//  SecureFileError.swift
//  SecureContainer
//
//  Created by Nick Bedford on 15/4/2026.
//

import Foundation

enum SecureFileError: Error
{
	case fileCreationError(URL)
	case fileLocked(URL)
	case fileMissing(URL)
	case invalidHeader(URL)
	case invalidFormat(URL)
	case invalidVersion(URL)
	case invalidStringConverson(URL)
	case invalidNonce(URL)
	case integerError
	case integerOverflowError
	case dataReadError
}
