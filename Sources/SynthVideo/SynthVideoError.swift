//
//  SynthVideoErrors.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 1/12/23.
//

import Foundation

public enum SynthVideoError : Error {
    // File errors
    case fileNotFound(filename: String, lineNumber: Int)
    case fileCorruption
    
    case permissionError
    
    // File export
    case outputFileUnavailable
    case invalidRange
    case notDirectory
    
    case invalidDelayValue
    case videoInitializationError
    
    // Native data types
    case invalidTileSize
    case invalidPosition
    case invalidPixelRow
    
    // Script initialization errors
    case missingGraphicFile
    case incorrectImageDimensions
    case unknownCommand(lineNumber: Int)
    case badArguments(command: String, lineNumber: Int)
    case unableToLoadImage (fileName: String, lineNumber: Int)
    case graphicConversionError
    case imageTooComplex
    case unsupportedCodec
    
    // Frame function
    case invalidFrameNumber
}

extension SynthVideoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let filename, let lineNumber):
            return "File not found on line \(lineNumber): \(filename)"
        case .fileCorruption:
            return "File corruption."
        case .permissionError:
            return "Permission error. Unable to read file."
        case .outputFileUnavailable:
            return "Output file unavailable"
        case .invalidRange:
            return "Invalid range selection"
        case .notDirectory:
            return "Given URL is not a directory"
        case .invalidDelayValue:
            return "Invalid delay value. Delay must be greater than 0, and in the 16-bit unsigned range."
        case .videoInitializationError:
            return "Unable to initialize Apple provided video frameworks."
        case .invalidTileSize:
            return "Invalid tile size. Size must be 8 x 12."
        case .invalidPosition:
            return "Invalid position"
        case .invalidPixelRow:
            return "Invalid pixel row"
        case .missingGraphicFile:
            return "Unable to find graphics file"
        case .incorrectImageDimensions:
            return "Incorrect image dimensions. Image must be nx400 x mx300."
        case .unknownCommand(let lineNumber):
            return "Unknown command on line \(lineNumber)"
        case .badArguments(let command, let lineNumber):
            return "Invalid arguments for command \(command) on line \(lineNumber)"
        case .unableToLoadImage(let fileName, let lineNumber):
            return "Unable to load image \(fileName) on line \(lineNumber)"
        case .graphicConversionError:
            return "Unable to process graphic image."
        case .imageTooComplex:
            return "Image too complex; More than 256 unique tiles required to display image."
        case .unsupportedCodec:
            return "Unsupported Codec."
        case .invalidFrameNumber:
            return "Invalid frame number."
        }
    }
}

