//
//  Screen.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 1/12/23.
//

import Foundation

public class Screen: Hashable, Equatable {
    let tilePositions: TilePositions
    let xOffset: UInt16
    let yOffset: UInt16
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.tilePositions)
        hasher.combine(self.xOffset)
        hasher.combine(self.yOffset)
    }
    
    public static func == (lhs: Screen, rhs: Screen) -> Bool {
        if lhs.tilePositions == rhs.tilePositions &&
            lhs.xOffset == rhs.xOffset &&
            lhs.yOffset == rhs.yOffset {
            return true
        } else {
            return false
        }
    }
    
    lazy var tiles: Set<Tile> = {
        return Set<Tile>(self.tilePositions.keys)
    }()

    
    init(tilePositions: TilePositions, xOffset: UInt16, yOffset: UInt16) {
        self.tilePositions = tilePositions
        // The x and y offsets are restricted to the range 0->799
        self.xOffset = xOffset % UInt16(vramPixelColumns)
        self.yOffset = yOffset % UInt16(vramPixelRows)
    }
    
    static let blank: Screen = {
        // Make a blank screen oriented at 0,0
        let blankTile = Tile.blank
        var tiles = TilePositions()
        tiles[blankTile] = {
            var positions = Set<TileMapPosition>()
            for row: UInt8 in 0...24 {
                for col: UInt8 in 0...49 {
                    positions.insert(TileMapPosition(row: row, col: col))
                }
            }
            return positions
        }()
        return Screen(tilePositions: tiles, xOffset: 0, yOffset: 0)
    }()
    
    lazy var screenPositions: Set<TileMapPosition> = {
        var positions = Set<TileMapPosition>()
        
        let startRow = (Int(yOffset) / 12) % vramTileRows
        let endRow = startRow + (yOffset % 12 == 0 ? 24 : 25)
        let startCol = (Int(xOffset) / 8) % vramTileColumns
        let endCol = startCol + (xOffset % 8 == 0 ? 49 : 50)
        
        for row in startRow...endRow {
            for col in startCol...endCol {
                let rowMod = UInt8(row % vramTileRows)
                let colMod = UInt8(col % vramTileColumns)
                
                positions.insert(TileMapPosition(row: rowMod, col: colMod))
            }
        }

        return positions
    }()
}
