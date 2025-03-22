//
//  MemoryStateTests.swift
//  
//
//  Created by Hayden McCabe on 7/25/23.
//

import XCTest
@testable import SynthVideo


final class MemoryStateTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        guard let scriptURL = Bundle.module.url(forResource: "Load256Tiles", withExtension: "script") else {
            XCTFail("Missing required test file \"ActiveBlack.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        
//        // Verify that the properties match what is expected from the script
//        XCTAssert(video.frames.count == 1)
//        // There should be one tile used, with each entry = 255
//        let tileSet = video.frames[0].tiles
//        XCTAssert(tileSet.count == 1)
//        XCTAssert(tileSet.contains(Tile.full))
//        XCTAssert(video.frames[0].xOffset == 0)
//        XCTAssert(video.frames[0].yOffset == 0)
        
        let memoryStates = video.memoryStates
                
        let tileMap = memoryStates[0].tileMap
        let tileLibrary = memoryStates[0].tileLibrary
        
        print("Tilemap:")
        for i in 0 ..< tileMap.count {
            let byte = tileMap[i]
            print("\(i): \(byte)")
        }
        print("\n\nLibrary")
        
        for i in 0 ..< tileLibrary.count {
            let byte = tileLibrary[i]
            if byte != 0 {
                print("Hello non zero")
            }
        }
    }

}
