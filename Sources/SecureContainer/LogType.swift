//
//  LogType.swift
//  SecureFile
//
//  Created by Nick Bedford on 21/4/2026.
//

public enum LogType: Sendable
{
	case notice
	case info
	case warning
	case error
	case performance
	case custom(String)
	
	var label: String
	{
		switch self
		{
			case .notice: return "NOTICE"
			case .info: return "INFO"
			case .warning: return "WARNING"
			case .error: return "ERROR"
			case .performance: return "PERF"
			case .custom(let label): return label
		}
	}
}
