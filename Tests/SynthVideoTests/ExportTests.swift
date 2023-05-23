//
//  ExportTests.swift
//  
//
//  Created by Hayden McCabe on 5/20/23.
//
import XCTest
@testable import SynthVideo

final class ExportTests: XCTestCase {

    func testSynthvidExport() throws {
        // Get a temp directory to export a file to
        let tempDirectory = FileManager.default.temporaryDirectory
        let exportedFileUrl = tempDirectory.appending(path: "testSynthvidExport.synthvid")
                
        guard let scriptURL = Bundle.module.url(forResource: "Load256Tiles", withExtension: "script") else {
            XCTFail()
            return
        }
        
        let video = try SynthVideo(script: scriptURL)

        // Try exporting to the temp directory
        XCTAssertNoThrow(try video.exportSynthvid(url: exportedFileUrl))
        
        // Load the file to see if it looks correct
        let data = try Data(contentsOf: exportedFileUrl)
        
        data.withUnsafeBytes { romPtr8 in
            // Create a UInt16 typed pointer
            let romPtr16 = romPtr8.bindMemory(to: UInt16.self)
            // There should be two 16-bit zero values representing
            // an offset of 0,0
            XCTAssert(romPtr16[0] == 0)
            XCTAssert(romPtr16[1] == 0)
            // There should be 256 tile library updates
            // and 255 tile map updates. The 256 tiles in the image
            // are new to the frame (none of the tiles are blank),
            // and the optimization stage of the export should have updated the
            // library to minimize writes, so that the most commonly used tile
            // is written to index 0.
            XCTAssert(romPtr16[2] == 256)
            XCTAssert(romPtr16[3] == 255)
            // The total size of the data block should be
            // + 8 bytes processed thus far
            // + 256 * 16 bytes for library updates
            // + 255 * 4 bytes for tilemap updates
            // + 4 bytes for the 0xDEADBEEF footer
            let expectedBytes = 8 + (256 * 16) + (255 * 4) + 4
            XCTAssert(data.count == expectedBytes)
        }
        
        let restoredVideo = try SynthVideo(synthvidData: data)
        XCTAssert(restoredVideo.frames.count == 1)
    }
}
