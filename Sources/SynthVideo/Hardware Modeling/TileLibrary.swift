//
//  TileLibrary.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 1/27/23.
//

import Foundation

// 256 value tile library with reverse lookup.
// Multiple tile library positions can be used
// for the same tile pattern.
public struct TileLibrary {
    // Model the 256 stored tiles as a Swift array, but restrict
    // the lookup to UInt8 values to correctly model the hardware.
    private(set) var tileForIndex = Array<Tile>(repeating: Tile.blank, count: 256)
    func tile(index: UInt8) -> Tile {
        tileForIndex[Int(index)]
    }
    subscript(_ index: UInt8) -> Tile {
        get {
            tileForIndex[Int(index)]
        }
        set {
            setTile(newValue, index: index)
        }
    }
    
    private(set) var indicesForTile: [Tile : Set<UInt8>] = [Tile.blank: Set<UInt8>(0...255)]
    mutating func setTile(_ tile: Tile, index: UInt8) {
        // Get the tile that currently occupies this space
        let oldTile = tileForIndex[Int(index)]
        
        // Update the reverse lookup
        indicesForTile[oldTile]!.remove(index)
        if indicesForTile[oldTile]!.count == 0 {
            indicesForTile[oldTile] = nil
        }
        
        if indicesForTile[tile] == nil {
            // This is the first record for this tile.
            // Create a new set for this index
            indicesForTile[tile] = Set<UInt8>(arrayLiteral: UInt8(index))
        } else {
            // There is a set for this tile; add this index to it
            indicesForTile[tile]!.insert(index)
        }
        
        // Commit the change
        tileForIndex[Int(index)] = tile;
    }
    
    var hasDuplicates: Bool {
        for indexSet in indicesForTile.values {
            if indexSet.count > 1 {
                return true
            }
        }
        return false
    }
}
