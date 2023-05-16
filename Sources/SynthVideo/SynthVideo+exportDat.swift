//
//  SynthVideo+exportDat.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 1/23/23.
//

import Foundation

typealias TileMapWrites = [TileMapPosition : UInt8]
typealias TileLibraryWrites = [UInt8 : Tile]

fileprivate struct ScreenUpdate {
    let xOffset: UInt16
    let yOffset: UInt16
    let tileMapWrites: TileMapWrites
    let tileLibraryWrites: TileLibraryWrites
}

extension SynthVideo {
    /// Export the current SynthVideo instance into a .dat file at the given URL
    public func exportDat(url: URL) throws {
        // Calculate the changes for each frame from the one that preceeded it.
        // Assume the first frame is preceeded by a blank screen.
        var screenUpdates = [ScreenUpdate?]()
        
        // Track the updates made to the tile map and tile library
        var tileMap = TileMap()
        var tileLibrary = TileLibrary()
        
        // Analyze the entire video, to find when each unique tile appears.
        var tileAppearances = self.tileAppearances
        
        // Track which tiles have made their final appearance, so that
        // they can be safely removed from the tile library
        var releasedTiles = Set<Tile>()
        
        for frameNumber in 0 ..< frames.count {
                        
            let previousScreen = (frameNumber == 0) ? Screen.blank : frames[frameNumber-1]
            let currentScreen = frames[frameNumber]
                        
            // Store the pending writes in dictionaries, to prevent duplicates
            // and ensure that only the last written value is used.
            var tileMapWrites = [TileMapPosition : UInt8]()
            var tileLibraryWrites = [UInt8 : Tile]()
            
            // Create a list of tiles that are released after this screen
            var upcomingReleases = [Tile]()
            
            // Consider each tile that will appear on screen, and their positions
            for (tile, positions) in currentScreen.tilePositions {
                // Sort the positions that will display this tile
                // by what tile library index they currently have.
                
                let positionsByOldIndex = {
                    var positionsByOldIndex = IndexPositions()
                    for position in positions {
                        let oldIndex = tileMap[position]
                        positionsByOldIndex.add(key: oldIndex, position: position)
                    }
                    return positionsByOldIndex
                }()
                
                // Iterate through the tiles, sorted by what value their
                // positions currently hold in the tile map
                for (oldIndex, insidePositions) in positionsByOldIndex {
                    let oldTile = tileLibrary[oldIndex]
                    
                    // If the tile index already points to the needed tile,
                    // continue.
                    if oldTile == tile {
                        continue
                    }
                    
                    // Find the mapping of existing tile map values visible on screen, sorted
                    // by index
                    let tileMapIndexPositions = tileMap.indexPositionsOnScreen(xOffset: currentScreen.xOffset, yOffset: currentScreen.yOffset)
                    
                    // It is more efficient to change the tile library entry for this index than
                    // to change the values in the tile map if:
                    // The number of positions in the drawing area using this tile index is greater than
                    // the number of positions on screen, outside of the drawing area, using the same
                    // tile pattern in both this screen and the previous.
                    let outsidePositions: Set<TileMapPosition> = {
                        tileMapIndexPositions[oldIndex]?.subtracting(insidePositions)
                            .filter({
                                // Filter to keep only positions that show
                                // this tile in both the previous and current
                                // frame.
                                currentScreen.tilePositions[oldTile]?.contains($0) ?? false
                            }) ?? Set<TileMapPosition>()
                    }()
                    
                    // See if it requires fewer moves to update the tile map
                    // or the tile library.
                    // TODO: Update to be based on total CPU cycles or file size
                    let updateLibrary = insidePositions.count > outsidePositions.count
                    
                    if (updateLibrary) {
                        // See how many writes are needed for writing without swapping
                        // a value in the tile library
                        var (standardTileMapWrites, standardTileLibraryWrites, standardReleasedTile) = writesToDraw(tile: tile, drawPositions: insidePositions, library: tileLibrary, tileMap: tileMap, screen: currentScreen, released: releasedTiles)
                        
                        // TODO: FIX ABOVE.
                        // Returns tile map writes that are for the data already in the map
                        // Returns a released value
                        
                        // If the standard approach found the same move as the swap by the space's
                        // availability as a releasable tile, it will have returned unneeded tile map
                        // writes which can be filtered out
                        standardTileMapWrites = standardTileMapWrites.filter { (position, index) in
                            return tileMap[position] != index
                        }
                        
                        // Create a copy of the library, changing the library value
                        // for this index to see how many writes would be needed
                        // to update the screen.
                        var swapLibrary = tileLibrary
                        swapLibrary[oldIndex] = tile
                        
                        // If the swap removed the last instance of a tile that is in the release pool,
                        // make the calculation with that tile removed from the pool
                        let swapReleased = swapLibrary.indicesForTile[oldTile] == nil ? releasedTiles.subtracting([oldTile]) : releasedTiles
                        
                        let (swapTileMapWrites, swapTileLibraryWrites, swapReleasedTile) = writesToDraw(tile: oldTile, drawPositions: outsidePositions, library: swapLibrary, tileMap: tileMap, screen: currentScreen, released: swapReleased)

                        // Find the number of writes needed for the two algorithms
                        let standardWrites = standardTileMapWrites.count + standardTileLibraryWrites.count
                        let swapWrites = swapTileMapWrites.count + swapTileLibraryWrites.count + 1
                        
                        // Do the final update based on which path requires fewer writes
                        if swapWrites < standardWrites {
                            // Swap
                            // See if the old tile removed in the swap needs to be removed from the library
                            //let swappedTile = tileLibrary[oldIndex]
                            tileLibrary[oldIndex] = tile
                            tileLibraryWrites[oldIndex] = tile
                            // See if the tile that was removed was in the release pool,
                            // and if it was the last instance of that tile, remove the
                            // tile from the pool.
                            if releasedTiles.contains(oldTile) {
                                if tileLibrary.indicesForTile[oldTile] == nil {
                                    releasedTiles.remove(oldTile)
                                }
                            }
                            
                            tileMapWrites.merge(swapTileMapWrites, uniquingKeysWith: replaceMerge)
                            tileLibraryWrites.merge(swapTileLibraryWrites, uniquingKeysWith: replaceMerge)
                            applyUpdates(mapWrites: swapTileMapWrites, libraryWrites: swapTileLibraryWrites, releasedTile: swapReleasedTile, tileMap: &tileMap, tileLibrary: &tileLibrary, released: &releasedTiles)
                        } else {
                            tileMapWrites.merge(standardTileMapWrites, uniquingKeysWith: replaceMerge)
                            tileLibraryWrites.merge(standardTileLibraryWrites, uniquingKeysWith: replaceMerge)
                            applyUpdates(mapWrites: standardTileMapWrites, libraryWrites: standardTileLibraryWrites, releasedTile: standardReleasedTile, tileMap: &tileMap, tileLibrary: &tileLibrary, released: &releasedTiles)
                        }
                                                

                    } else {
                        // Add the update events to the array
                        let (newTileMapWrites, newTileLibraryWrites, newReleasedTile) = writesToDraw(tile: tile, drawPositions: insidePositions, library: tileLibrary, tileMap: tileMap, screen: currentScreen, released: releasedTiles)
                        tileMapWrites.merge(newTileMapWrites, uniquingKeysWith: replaceMerge)
                        tileLibraryWrites.merge(newTileLibraryWrites, uniquingKeysWith: replaceMerge)
                        applyUpdates(mapWrites: newTileMapWrites, libraryWrites: newTileLibraryWrites, releasedTile: newReleasedTile, tileMap: &tileMap, tileLibrary: &tileLibrary, released: &releasedTiles)
                    }
                }
                
                if tileAppearances[tile]!.last! == frameNumber {
                    upcomingReleases.append(tile)
                    // Remove the tile from tileAppearances so there are
                    // fewer to search through in the future
                    tileAppearances.removeValue(forKey: tile)
                } else {
                    tileAppearances[tile]!.remove(at: 0)
                }
                
                // Write any changes to the tile map and tile library for the
                // next iteration.
                for write in tileMapWrites {
                    tileMap[write.key] = write.value
                }
                for write in tileLibraryWrites {
                    tileLibrary[write.key] = write.value
                }
            }
            
            // Update the releasedTiles set with tiles last used in this frame
            for release in upcomingReleases {
                releasedTiles.insert(release)
            }
            
            // If there are no updates, insert nil into the updates array.
            // Otherwise, format the screen update and insert it to the array.
            if (currentScreen.xOffset == previousScreen.xOffset &&
                currentScreen.yOffset == previousScreen.yOffset &&
                tileMapWrites.isEmpty && tileLibraryWrites.isEmpty) {
                screenUpdates.append(nil)
            } else {
                let screenUpdate = ScreenUpdate(xOffset: currentScreen.xOffset, yOffset: currentScreen.yOffset, tileMapWrites: tileMapWrites, tileLibraryWrites: tileLibraryWrites)
                screenUpdates.append(screenUpdate)
            }
        }
        
        print("Writing \(screenUpdates.count) frames to file")
        
        // Write the updates into the dat file format.
        var outputData = Data()
        
        var delayCount: UInt16 = 0
        
        for update in screenUpdates {
            if let update {
                // Write any pending delays
                if delayCount > 0 {
                    outputData.appendUInt16(0xBABE)
                    outputData.appendUInt16(delayCount)
                }
                delayCount = 0
                // Write the x and y offsets
                outputData.appendUInt16(update.xOffset)
                outputData.appendUInt16(update.yOffset)
                
                // Write the respective update counts
                outputData.appendUInt16(UInt16(update.tileLibraryWrites.count))
                outputData.appendUInt16(UInt16(update.tileMapWrites.count))
                
                // Write the library updates. Each update takes 16 bytes of space
                let orderedLibraryUpdates = update.tileLibraryWrites.sorted { first, second in
                    return first.key < second.key
                }
                for libUpdate in orderedLibraryUpdates {
                    // The UInt8 index number is written as a UInt32 value
                    // in little endian format to preserve alignment
                    outputData.append(contentsOf: [libUpdate.key, 0, 0, 0])
                    outputData.append(contentsOf: libUpdate.value.pixels)
                }
                
                // Write the tilemap updates.
                let orderedTileMapUpdates = update.tileMapWrites.sorted { first, second in
                    return first.key < second.key
                }
                for tileMapUpdate in orderedTileMapUpdates {
                    // Write the coordinates for the tile, followed by the library index and 0
                    outputData.append(contentsOf: [tileMapUpdate.key.row, tileMapUpdate.key.col, tileMapUpdate.value, 0])
                }
            } else {
                delayCount += 1
            }
        }
        // Write any delays from the end of the video
        if delayCount > 0 {
            outputData.appendUInt16(0xBABE)
            outputData.appendUInt16(delayCount)
        }
        
        // Finish off the file with 0xBEEF 0xCAFE
        outputData.appendUInt16(0xBEEF)
        outputData.appendUInt16(0xCAFE)
        
        // Write the data to file
        try! outputData.write(to: url)
        print("Done writing file!")
    }

    /// Return a dictionary that maps each tile that appears in the video to its appearances.
    /// This allows the optimization stage of exporting to .dat to free references to a tile once
    /// it is no longer needed.
    fileprivate var tileAppearances: [Tile : [Int]] {
        var appearances = [Tile : [Int]]()
        
        for (frameNumber, frame) in frames.enumerated() {
            for tile in frame.tilePositions.keys {
                // If this tile has been seen before, append this frame number.
                // If it has been seen before, append this appearance.
                if appearances[tile] != nil {
                    appearances[tile]!.append(frameNumber)
                } else {
                    appearances[tile] = [frameNumber]
                }
            }
        }
        
        return appearances
    }
}

/// Find which write operations are required to make write the given tile at the given positions into a library and tilemap, in the context of a screen, knowing that a set of tiles
/// are no longer needed.
fileprivate func writesToDraw(tile: Tile, drawPositions: Set<TileMapPosition>, library: TileLibrary, tileMap: TileMap, screen: Screen, released: Set<Tile>) -> (tileMapWrites: TileMapWrites, tileLibraryWrites : TileLibraryWrites, releasedTile: Tile?) {
    
    var tileMapWrites = TileMapWrites()
    var tileLibraryWrites = TileLibraryWrites()
    
    // If the tile is already in the library, simply do the writes
    // using the library index that already has the most appearances
    // in the tile map
    if let matchingIndices = library.indicesForTile[tile] {
        // Sort the matches by:
        // 1: Number of positions using the index on screen
        // 2: Number of positions using the index total
        // 3: Index number
        let writeIndex: UInt8 = {
            // Map the indices to tuples containing the
            // sort parameters, sort, and return the first one
            matchingIndices.map { index in
                let allPositions = tileMap.positionsByIndex[Int(index)]
                let onscreenPositions = allPositions.intersection(screen.screenPositions)

                return (onScreen: onscreenPositions.count, inMap: allPositions.count, index: index)
            }.sorted { first, second in
                // Prefer the fewest positions on-screen
                if (first.onScreen < second.onScreen) {
                    return true
                } else if (first.onScreen > second.onScreen) {
                    return false
                }
                // Next prefer the fewest positions overall
                if (first.inMap < second.inMap) {
                    return true
                } else if (first.inMap > second.inMap) {
                    return false
                }
                // Finally, prefer the lowest index
                if (first.index < second.index) {
                    return true
                } else {
                    return false
                }
            }.first!.index
            
        }()

        for drawPosition in drawPositions {
            tileMapWrites[drawPosition] = writeIndex
        }
        return (tileMapWrites, tileLibraryWrites, nil)
    }
    
    // If the tile is not in the library, see if there is a released tile space that can be used
    if released.count > 0 {
        // Use the first index that appears in the release pool
        let (writeIndex, releasedTile) = {
            let (writeIndexInt, releasedTile) = library.tileForIndex.enumerated().first { (_, potentialRelease) in
                released.contains(potentialRelease)
            }!
            
            return (UInt8(writeIndexInt), releasedTile)
        }()

        // Update the tile library
        tileLibraryWrites[writeIndex] = tile
                
        for drawPosition in drawPositions {
            tileMapWrites[drawPosition] = writeIndex
        }
        return (tileMapWrites, tileLibraryWrites, releasedTile)
    }
    
    // See if there is a tile pattern occupying multiple positions in the tile library,
    // consolodate the tiles into one library index, and adjust the tile map as needed.
    if library.hasDuplicates {
        // Filter the library down to the tiles with duplicate indices
        let duplicates = library.indicesForTile.filter { indices in
            indices.value.count > 1
        }
        // This should only occur if bad data was passed in; no valid screen should contain more
        // than 256 unique tiles
        if duplicates.isEmpty {
            fatalError()
        }
        
        // Sort all duplicate indices by:
        // 1: Fewest appearances on screen
        // 2: Fewest appearances in the map
        // 3: Lowest index
        let writeIndex: UInt8 = {
            // Reduce to a set of all indices of duplicates.
            // e.g., if a tile were at indices 0 and 1, both will appear
            // in the resulting set
            let allIndices = duplicates.values.reduce([UInt8]()) { partialResult, indices in
                return partialResult + Array(indices)
            }
            // Map the indices to tuples of the sorting criteria, then
            // sort to find the best choice and return it
            let sorted = allIndices.map { index in
                let allPositions = tileMap.positionsByIndex[Int(index)]
                let onScreenPositions = allPositions.intersection(screen.screenPositions)
                return (onScreen: onScreenPositions.count, inMap: allPositions.count, index: index)
            }
            .sorted { first, second in
                // Prefer fewer positions on screen
                if first.onScreen < second.onScreen {
                    return true
                } else if first.onScreen > second.onScreen {
                    return false
                }
                // Prefer fewer positions in the tilemap overall
                if first.inMap < second.inMap {
                    return true
                } else if first.inMap > second.inMap {
                    return false
                }
                
                // Prefer the lower index
                if first.index < second.index {
                    return true
                } else {
                    return false
                }
            }
            
            return sorted.first!.index
        }()
        // Find the index of this tile with the most
        // usage in the current tile map (excluding
        // the write index)
        let mergeTile = library.tileForIndex[Int(writeIndex)]
        let mergeIndex: UInt8 = {
            // Find all indices for the selected tile except for writeIndex.
            
            let tileIndices = library.indicesForTile[mergeTile]!.subtracting([writeIndex])
            // Map the indices into tuples for sorting
            let sorted = tileIndices.map { index in
                // Find the number of appearances for each index
                let appearanceCount = tileMap.positions(for: index).count
                return (appearances: appearanceCount, index: index )
            }
            .sorted { first, second in
                // Prefer the highest count
                if first.appearances > second.appearances {
                    return true
                } else if first.appearances < second.appearances {
                    return false
                }
                // Prefer the lower index
                if first.index < second.index {
                    return true
                } else {
                    return false
                }
            }
            return sorted.first!.index
        }()
        
        // Change every on-screen position using writeIndex that
        // will continue to show the same tile in the current frame
        // to use mergeIndex
        // TODO: Update to consider only tiles that need to be maintained
        // Find the positions that use the merge index on-screen, then filter them
        // to the positions that will continue to show this tile
        let changePositions = tileMap.positions(for: writeIndex)
            .intersection(screen.screenPositions)
            .intersection(screen.tilePositions[mergeTile] ?? Set<TileMapPosition>())
        
        for position in changePositions {
            tileMapWrites[position] = mergeIndex
        }
        
        // Update writeIndex to use the new tile
        tileLibraryWrites[writeIndex] = tile
        
        // Update the draw positions to use writeIndex
        for position in drawPositions {
            tileMapWrites[position] = writeIndex
        }
        
        return (tileMapWrites, tileLibraryWrites, nil)
    }
    
    // Finally, address the situation where a tile must be freed now, though it
    // will appear again later.
    
    // Create a set of tiles that are in the tile library, but not in the current screen
    let tilesInLibrary = Set<Tile>(library.tileForIndex)
    let removeableTiles = tilesInLibrary.subtracting(screen.tiles)
    
    // TODO: Find an optimal tile to use
    guard removeableTiles.count > 0 else {
        fatalError()
    }
    let removedTile = removeableTiles.first!
    let writeIndex = library.indicesForTile[removedTile]!.first!
    
    // Load the tile
    tileLibraryWrites[writeIndex] = tile
    
    // Update the tile map
    for drawPosition in drawPositions {
        tileMapWrites[drawPosition] = writeIndex
    }
    return (tileMapWrites, tileLibraryWrites, nil)
}

/// Apply the sets of writes returned from writesToDraw(::::::) into the given tilemap, library, and set of released tiles.
fileprivate func applyUpdates(mapWrites: TileMapWrites, libraryWrites: TileLibraryWrites, releasedTile: Tile?, tileMap: inout TileMap, tileLibrary: inout TileLibrary, released: inout Set<Tile>) {
    for mapWrite in mapWrites {
        tileMap[mapWrite.key] = mapWrite.value
    }
    for libraryWrite in libraryWrites {
        tileLibrary[libraryWrite.key] = libraryWrite.value
    }
    if let releasedTile {
        // If the tile that was released is no longer in
        // the tile library, remove it from the release pool.
        if tileLibrary.indicesForTile[releasedTile] == nil {
            released.remove(releasedTile)
        }
        
    }
}

/// Convenience method used as an argument to the .merge method of Dictionary, so that duplicate entries are replaced.
fileprivate func replaceMerge<T> (oldValue: T, newValue: T) -> T {
    newValue
}

/// Convenience method to append a 16-bit value into a Data struct in little-endian order.
fileprivate extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        // Append the bytes in little endian order
        let bytes = [UInt8(value & 0xFF), UInt8(value >> 8)]
        self.append(contentsOf: bytes)
    }
}
