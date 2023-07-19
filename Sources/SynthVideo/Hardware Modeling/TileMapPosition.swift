//
//  SmallTypes.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 1/12/23.
//

import Foundation

/// A position for a tile in the tilemap. The row value is in the range 0...49
/// and the column value is in the range 0...99
public struct TileMapPosition: Hashable {
    let row: UInt8
    let col: UInt8
    
    /// Create a new TileMapPosition
    ///
    /// - Parameter row: A row in the range 0...49
    /// - Parameter col: A column in the range 0...99
    ///
    /// - Throws: SynthVideoError.invalidPixelRow when row >= 50
    /// - Throws: SynthVideoError.invalidPixelColumn when col >= 100
    init(row: UInt8, col: UInt8) throws {
        guard row < vramTileRows else {
            throw SynthVideoError.invalidPixelRow
        }
        guard col < vramTileColumns else {
            throw SynthVideoError.invalidPixelColumn
        }
        self.row = row
        self.col = col
    }
}

internal typealias TilePositions = [Tile : Set<TileMapPosition>]
internal typealias IndexPositions = [UInt8 : Set<TileMapPosition>]

internal extension Dictionary where Value == Set<TileMapPosition> {
    mutating func add(key: Key, position: TileMapPosition) {
        if self[key] != nil {
            self[key]!.insert(position)
        } else {
            self[key] = [position]
        }
    }
}

extension TileMapPosition: Comparable {
    
    public static func < (lhs: TileMapPosition, rhs: TileMapPosition) -> Bool {
        if lhs.row < rhs.row {
            return true
        } else if lhs.row > rhs.row {
            return false
        }
        
        if lhs.col < rhs.col {
            return true
        } else {
            return false
        }
    }
}

extension TileMapPosition: CustomStringConvertible {
    public var description: String {
        return "(\(self.row), \(self.col))"
    }
}
