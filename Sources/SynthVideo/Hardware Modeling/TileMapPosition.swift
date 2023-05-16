//
//  SmallTypes.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 1/12/23.
//

import Foundation

/// A position for a tile in the tilemap.
///  - row: A row in the range 0...49
///  - col: A column in the range 0...99
public struct TileMapPosition: Hashable {
    let row: UInt8
    let col: UInt8
}

public typealias TilePositions = [Tile : Set<TileMapPosition>]
public typealias IndexPositions = [UInt8 : Set<TileMapPosition>]

public extension Dictionary where Value == Set<TileMapPosition> {
    mutating func add(key: Key, position: TileMapPosition) {
        if self[key] != nil {
            self[key]!.insert(position)
        } else {
            self[key] = [position]
        }
    }
}

extension TileMapPosition: Comparable, CustomStringConvertible {
    public var description: String {
        return "(\(self.row), \(self.col))"
    }
    
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
