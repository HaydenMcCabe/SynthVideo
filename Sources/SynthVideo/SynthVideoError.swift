//
//  SynthVideoErrors.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 1/12/23.
//

import Foundation

public enum SynthVideoError : Error, CaseIterable {
    // File errors
    case fileNotFound
    case fileCorruption
    case permissionError
    
    // File export
    case outputFileUnavailable
    case invalidRange
    case notDirectory
    case unsupportedCodec
    
    // OS issues
    case videoInitializationError
    case graphicsConversionError
    
    // Native data types
    case invalidTileSize
    case invalidPosition
    case invalidPixelRow
    case invalidPixelColumn
    
    // Empty video when initializing from an empty script
    case emptyVideo
    
    // Frame
    case invalidFrameNumber
}

public enum SynthVideoScriptError : Error {
    case missingGraphicFile(lineNumber: Int)
    case incorrectImageDimensions(lineNumber: Int)
    case unknownCommand(lineNumber: Int)
    case badArguments(lineNumber: Int)
    case unableToLoadImage (lineNumber: Int)
    case graphicConversionError(lineNumber: Int)
    case imageTooComplex(lineNumber: Int)
    case invalidDelayValue(lineNumber: Int)
    
}

extension SynthVideoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .fileCorruption:
            return "File corruption"
        case .permissionError:
            return "User does not have sufficient permissions for file operation"
            
        case .outputFileUnavailable:
            return "Output file unavailable"
        case .invalidRange:
            return "Invalid range selection"
        case .notDirectory:
            return "Given URL is not a directory"
        case .unsupportedCodec:
            return "Given codec is not supported for video export"
            
        case .videoInitializationError:
            return "Unable to initialize Apple provided video frameworks"
        case .graphicsConversionError:
            return "Unable to initialize Apple provided graphics frameworks"
            
        case .invalidTileSize:
            return "Invalid tile size. Size must be 8 x 12"
        case .invalidPosition:
            return "Invalid position"
        case .invalidPixelRow:
            return "Invalid pixel row"
        case .invalidPixelColumn:
            return "Invalid pixel column"
            
        case .emptyVideo:
            return "Resulting video has no frames"
            
        case .invalidFrameNumber:
            return "Invalid frame number."
        }
    }
}

