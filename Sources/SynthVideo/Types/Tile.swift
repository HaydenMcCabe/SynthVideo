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
    
    /// The pixel data of the tile, represented as an array of UInt8 values.
    /// Each UInt8 value represents a bitmask of pixels in a row, with the
    /// MSB representing the left side. The first element of the array represents
    /// the top line.
    let pixels: [UInt8]
    
    /// Initialize a Tile from an array of UInt8 values. The initializer throws if the
    /// count of the given array is not 12
    /// - Parameter pixels: An array of UInt8 values representing the bitmask of
    /// active pixels in the tile, with the first element of the array representing the top line
    /// and so on.
    /// - Throws: `SynthVideoError.invalidTileSize` when the count of the `pixels` array is not 12
    init(pixels: [UInt8]) throws {
        guard pixels.count == 12 else {
            throw SynthVideoError.invalidTileSize
        }
        self.pixels = pixels
    }
    
    /// Return a UInt8 value representing the pixels in a row of the tile.
    ///
    /// - Parameter row: The row of pixels, in the range 0...11
    ///
    /// - Throws: `SynthVideoError.invalidPixelRow`
    ///       When the row argument is outside of the range 0...11
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
    
    /// A tile with all active pixels
    static var full: Tile {
        let fullTile = Array<UInt8>(repeating: 255, count: 12)
        return try! Tile(pixels: fullTile)
    }
    
    /// A tile with randomly lit pixels.
    static func random() -> Tile {
        return try! Tile(pixels: [
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255)
        ])
    }
}
