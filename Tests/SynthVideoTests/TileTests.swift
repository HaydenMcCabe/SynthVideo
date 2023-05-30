//
//  TileTests.swift
//  
//
//  Created by Hayden McCabe on 5/23/23.
//

import XCTest
@testable import SynthVideo

final class TileTests: XCTestCase {

    func testTileInitialization() {
        // Verify that some random Tiles can be created,
        // and that the values passed in are the values
        // in the initialized Tile.
        for _ in 1...10 {
            let randomArray: [UInt8] = [
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
            ]
            
            do {
                let newTile = try Tile(pixels: randomArray)
                XCTAssert(newTile.pixels == randomArray)
            } catch {
                XCTFail()
                return
            }
        }
        
        // Send pixel arrays with too few and too many
        // elements and verify that errors are thrown
        for elementCount in 0 ..< 12 {
            let smallArray = [UInt8](repeating: 0, count: elementCount)
            XCTAssertThrowsError( _ = try Tile(pixels: smallArray))
        }
        
        let largeArray = [UInt8](repeating: 0, count: 13)
        XCTAssertThrowsError( _ = try Tile(pixels: largeArray))
    }
    
    func testFullTile() {
        for row in Tile.full.pixels {
            XCTAssert(row == 255)
        }
    }
    
    func testPixelRow() {
        let randomTile = Tile.random()
        do {
            for rowIndex in 0 ..< 12 {
                let fetchedRow = try randomTile.pixelRow(rowIndex)
                XCTAssert(randomTile.pixels[rowIndex] == fetchedRow)
            }
        } catch {
            XCTFail()
            return
        }
        
        // Verify that passing negative values to pixelRow throws an error
        for _ in 1...10 {
            let negativeIndex = Int.random(in: Int.min ..< 0)
            XCTAssertThrowsError( _ = try randomTile.pixelRow(negativeIndex) )
        }
        
        // Verify that values greater than or equal to 12 throw an error
        for _ in 1...10 {
            let overflowIndex = Int.random(in: 12...Int.max)
            XCTAssertThrowsError( _ = try randomTile.pixelRow(overflowIndex))
        }
        
    }
    
    func testBlankTile() {
        for row in Tile.blank.pixels {
            XCTAssert(row == 0)
        }
    }
    
    func testTileOrdering() throws {
        // Generate an array of random UInt8 values
        let randomNumbers = {
            var numbers = [UInt8]()
            for _ in 1 ... 100 {
                numbers.append(UInt8.random(in: 0 ... 255))
            }
            return numbers
        }()
        
        let sortedNumbers = randomNumbers.sorted()
        
        for row in 0 ..< 12 {
            var tiles = [Tile]()
            let header = [UInt8](repeating: 0, count: row)
            let footer = [UInt8](repeating: 0, count: 11 - row)
            
            // Generate tiles from the random data
            for number in randomNumbers {
                try tiles.append(Tile(pixels: header + [number] + footer))
            }
            
            let sortedTiles = tiles.sorted()
            
            // Verify that the tiles are in the same order as
            // the sorted numbers
            let zipped = zip(sortedNumbers, sortedTiles)
            
            for (number, tile) in zipped {
                let pixelRow = try tile.pixelRow(row)
                XCTAssert(number == pixelRow)
            }
        }
    }

}
