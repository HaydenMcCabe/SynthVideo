//
//  Tile.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 1/12/23.
//

import Foundation

/// The tiles used in the synth video system. Each tile is composed of 12
/// UInt8 values, each representing a row of pixels, ordered from top to bottom
public struct Tile: Equatable, Comparable, Hashable {
    public static func < (lhs: Tile, rhs: Tile) -> Bool {
        for row in 0 ..< 12 {
            if lhs.pixels[row] < rhs.pixels[row] {
                return true
            } else if lhs.pixels[row] > rhs.pixels[row] {
                return false
            }
        }
        return true
    }
    
    let pixels: [UInt8]
    
    init(pixels: [UInt8]) throws {
        guard pixels.count == 12 else {
            throw SynthVideoError.invalidTileSize
        }
        self.pixels = pixels
    }
    
    /// Return a UInt8 value representing the pixels in a row of the tile.
    ///
    /// - Parameter row: The row of pixels, in the range 0...7
    ///
    /// - Throws: `SynthVideoError.invalidPixelRow`
    ///       The row argument is outside of the range 0...7
    ///
    /// - Returns: A UInt8 value representing the pixels in a row of the tile.
    func pixelRow(_ row: Int) throws -> UInt8 {
        guard row >= 0, row < 12 else {
            throw SynthVideoError.invalidPixelRow
        }
        return pixels[row]
    }
    
    /// A tile with no active pixels.
    static var blank: Tile {
        let blankTile = Array<UInt8>(repeating: 0, count: 12)
        return try! Tile(pixels: blankTile)
    }
    
    static var full: Tile {
        let fullTile = Array<UInt8>(repeating: 255, count: 12)
        return try! Tile(pixels: fullTile)

    }
}
