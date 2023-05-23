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

}
