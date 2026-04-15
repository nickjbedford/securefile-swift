//
//  EncryptionMethod.swift
//  SecureFile
//
//  Created by Nick Bedford on 15/4/2026.
//

/// The format used to encrypt a secure file's contents. This is typically
/// the encryption method used, such as AES-GCM encryption.
public enum EncryptionMethod: Int8, Sendable
{
	public static let best = EncryptionMethod.aesGcm
	
	/// Use AES-GCM encryption with a 96-bit nonce.
	case aesGcm = 0
	
	/// Specifies the nonce-length in bytes.
	var nonceLength: Int
	{
		get
		{
			switch self
			{
				case .aesGcm:
					return 12
			}
		}
	}
	
	/// Specifies the current version of the format.
	var currentVersion: Int8
	{
		get
		{
			switch self
			{
				case .aesGcm:
					return 1
			}
		}
	}
	
	/// Specifies the available versions of the format.
	var versions: [Int8]
	{
		get
		{
			switch self
			{
				case .aesGcm:
					return [1]
			}
		}
	}
}
