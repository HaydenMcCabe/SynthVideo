//
//  TileMap.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 2/13/23.
//

import Foundation

public struct TileMap {
    // Use a two-dimensional Swift array of UInt8 values to model
    // the tilemap used in the video hardware.
    private var values: [[UInt8]] = {
        let blankRow = [UInt8](repeating: 0, count: vramTileColumns)
        return [[UInt8]](repeating: blankRow, count: vramTileRows)
    }()
    // Access to the tilemap values requires UInt8 values for the
    // row and column to match the implementation in hardware
    subscript(position: TileMapPosition) -> UInt8 {
        get {
            values[Int(position.row)][Int(position.col)]
        }
        set(newValue) {
            try! setValue(value: newValue, row: position.row, col: position.col)
        }
    }
    
    func value(row: UInt8, col: UInt8) -> UInt8 {
        values[Int(row)][Int(col)]
    }
    
    mutating func setValue(value: UInt8, row: UInt8, col: UInt8) throws {
        let position = try TileMapPosition(row: row, col: col)
        // The old index should no longer contain this position
        let oldIndex = values[Int(row)][Int(col)]
        positionsByIndex[Int(oldIndex)].remove(position)
        
        // Update the new index to say it now contains this position
        positionsByIndex[Int(value)].insert(position)
        
        // Write the change
        values[Int(row)][Int(col)] = value
    }
    
    // Reverse lookup of tile map positions for positions
    // with a specific tile library index
    
    private(set) var positionsByIndex: [Set<TileMapPosition>] = {
        // When initialized, index 0 is at every position
        var positionArray = [Set<TileMapPosition>]()
        positionArray.reserveCapacity(256)
        // Create a set of every position
        var allPositions = Set<TileMapPosition>()
        for row: UInt8 in 0 ..< UInt8(vramTileRows) {
            for col: UInt8 in 0 ..< UInt8(vramTileColumns) {
                allPositions.insert(try! TileMapPosition(row: row, col: col))
            }
        }
        positionArray.append(allPositions)
        let emptySet = Set<TileMapPosition>()
        for _ in 1 ... 255 {
            positionArray.append(emptySet)
        }
        return positionArray
    }()

    func positions(for index: UInt8) -> Set<TileMapPosition> {
        return positionsByIndex[Int(index)]
    }
    
    // Return positions visible on screen with the given offset, sorted by index
    func indexPositionsOnScreen(xOffset: UInt16, yOffset: UInt16) -> IndexPositions {
        // Fetch the positions for the given offset
        let positions = TileMap.positions(xOffset: xOffset, yOffset: yOffset)
        
        // Create an instance to hold our results
        var indexPositions = IndexPositions()
        
        for position in positions {
            let index = self[position]
            indexPositions.add(key: index, position: position)
        }
        
        return indexPositions
    }
    
    static func positions(xOffset: UInt16, yOffset: UInt16) -> Set<TileMapPosition> {
        var positions = Set<TileMapPosition>()
        
        let startRow = (Int(yOffset) / 12) % vramTileRows
        let endRow = startRow + (yOffset % 12 == 0 ? 24 : 25)
        let startCol = (Int(xOffset) / 8) % vramTileColumns
        let endCol = startCol + (xOffset % 8 == 0 ? 49 : 50)
        
        for row in startRow...endRow {
            for col in startCol...endCol {
                let rowMod = UInt8(row % vramTileRows)
                let colMod = UInt8(col % vramTileColumns)
                
                positions.insert(try! TileMapPosition(row: rowMod, col: colMod))
            }
        }

        return positions
    }
}
