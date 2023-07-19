import XCTest
@testable import SynthVideo

/// This suite of tests cover initialization from script files,
/// the various commands used in those scripts
final class ScriptInitializationTests: XCTestCase {
    
    // MARK: Empty files
    
    func testEmptyFile() throws {
        guard let scriptURL = Bundle.module.url(forResource: "EmptyFile", withExtension: "script") else {
            XCTFail("Missing required test file \"EmptyFile.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoError.emptyVideo = error else {
                XCTFail("Returned error should be .emptyVideo")
                return
            }
        }
    }
    
    func testInvalidCommands() throws {
        guard let scriptURL = Bundle.module.url(forResource: "InvalidCommands", withExtension: "script") else {
            XCTFail("Missing required test file \"InvalidCommands.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.unknownCommand = error else {
                XCTFail("Returned error should be .unknownCommand")
                return
            }
        }
    }
    
    func testOnlyComments() throws {
        guard let scriptURL = Bundle.module.url(forResource: "OnlyComments", withExtension: "script") else {
            XCTFail("Missing required test file \"OnlyComments.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoError.emptyVideo = error else {
                XCTFail("Returned error should be .emptyVideo")
                return
            }
        }
    }
    
    // MARK: ActiveBlack
    
    func testActiveBlack() throws {
        guard let scriptURL = Bundle.module.url(forResource: "ActiveBlack", withExtension: "script") else {
            XCTFail("Missing required test file \"ActiveBlack.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        // Verify that the properties match what is expected from the script
        XCTAssert(video.frames.count == 1)
        // There should be one tile used, with each entry = 255
        let tileSet = video.frames[0].tiles
        XCTAssert(tileSet.count == 1)
        XCTAssert(tileSet.contains(Tile.full))
        XCTAssert(video.frames[0].xOffset == 0)
        XCTAssert(video.frames[0].yOffset == 0)
    }

    func testActiveBlackInverted() throws {
        guard let scriptURL = Bundle.module.url(forResource: "ActiveBlackInverted", withExtension: "script") else {
            XCTFail("Missing required test file \"ActiveBlackInverted.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        // Verify that the properties match what is expected from the script
        XCTAssert(video.frames.count == 1)
        // There should be one tile used, with each entry = 0
        let tileSet = video.frames[0].tiles
        XCTAssert(tileSet.count == 1)
        XCTAssert(tileSet.contains(Tile.blank))
        XCTAssert(video.frames[0].xOffset == 0)
        XCTAssert(video.frames[0].yOffset == 0)
    }
    
    // The ActiveBlack command does not take any arguments,
    // so their presence throws an error.
    func testActiveBlackArguments() throws {
        guard let scriptURL = Bundle.module.url(forResource: "ActiveBlackArguments", withExtension: "script") else {
            XCTFail("Missing required test file \"ActiveBlackArguments.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.badArguments = error else {
                XCTFail("Returned error should be .badArguments")
                return
            }
        }
    }
    
    // MARK: ActiveWhite
    
    func testActiveWhite() throws {
        guard let scriptURL = Bundle.module.url(forResource: "ActiveWhite", withExtension: "script") else {
            XCTFail("Missing required test file \"ActiveWhite.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        // Verify that the properties match what is expected from the script
        XCTAssert(video.frames.count == 1)
        // There should be one tile used, with each entry = 255
        let tileSet = video.frames[0].tiles
        XCTAssert(tileSet.count == 1)
        XCTAssert(tileSet.contains(Tile.full))
        XCTAssert(video.frames[0].xOffset == 0)
        XCTAssert(video.frames[0].yOffset == 0)
    }

    func testActiveWhiteInverted() throws {
        guard let scriptURL = Bundle.module.url(forResource: "ActiveWhiteInverted", withExtension: "script") else {
            XCTFail("Missing required test file \"ActiveWhiteInverted.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        // Verify that the properties match what is expected from the script
        XCTAssert(video.frames.count == 1)
        let tileSet = video.frames[0].tiles
        XCTAssert(tileSet.count == 1)
        XCTAssert(tileSet.contains(Tile.blank))
        XCTAssert(video.frames[0].xOffset == 0)
        XCTAssert(video.frames[0].yOffset == 0)
    }
    
    // The ActiveWhite command does not take any arguments,
    // so their presence throws an error.
    func testActiveWhiteArguments() throws {
        guard let scriptURL = Bundle.module.url(forResource: "ActiveWhiteArguments", withExtension: "script") else {
            XCTFail("Missing required test file \"ActiveWhiteArguments.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.badArguments = error else {
                XCTFail("Returned error should be .badArguments")
                return
            }
        }
    }
    
    // MARK: Load
    
    // Load an image which requires 256 unique tiles to display
    // and verify the resulting SynthVideo reflects that
    func testLoad256Tiles() throws {
        guard let scriptURL = Bundle.module.url(forResource: "Load256Tiles", withExtension: "script") else {
            XCTFail("Missing required test file \"Load256Tiles.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        // Verify that the properties match what is expected from the script
        XCTAssert(video.frames.count == 1)
        let tileSet = video.frames[0].tiles
        XCTAssert(tileSet.count == 256)
        XCTAssert(video.frames[0].xOffset == 0)
        XCTAssert(video.frames[0].yOffset == 0)
    }
    
    // Using the load command with an image file name
    // that can not be found relative to the working
    // directory
    func testLoadMissingFile() throws {
        guard let scriptURL = Bundle.module.url(forResource: "LoadMissingFile", withExtension: "script") else {
            XCTFail("Missing required test file \"LoadMissingFile.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.unableToLoadImage = error else {
                XCTFail("Returned error should be .unableToLoadImage")
                return
            }
        }
    }

    // Using the load command with a file that can not
    // be loaded as image data throws an error
    func testLoadInvalidImage() throws {
        guard let scriptURL = Bundle.module.url(forResource: "LoadInvalidImageFile", withExtension: "script") else {
            XCTFail("Missing required test file \"LoadInvalidImageFile.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.unableToLoadImage = error else {
                XCTFail("Returned error should be .unableToLoadImage")
                return
            }
        }
    }
    
    // Loading an image whose width is not congruent to
    // 0 mod 400 throws an error.
    func testLoadWideImage() throws {
        guard let scriptURL = Bundle.module.url(forResource: "LoadWideImage", withExtension: "script") else {
            XCTFail("Missing required test file \"LoadWideImage.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.incorrectImageDimensions = error else {
                XCTFail("Returned error should be .incorrectImageDimensions")
                return
            }
        }
    }
    
    // Loading an image whose height is not congruent to
    // 0 mod 300 throws an error.
    func testLoadTallImage() throws {
        guard let scriptURL = Bundle.module.url(forResource: "LoadTallImage", withExtension: "script") else {
            XCTFail("Missing required test file \"LoadTallImage.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.incorrectImageDimensions = error else {
                XCTFail("Returned error should be .incorrectImageDimensions")
                return
            }
        }
    }
    
    // Loading an image at an offset that would require
    // more than 256 unique tiles to be on screen at once
    // will throw an error.
    func testLoad257Tiles() throws {
        guard let scriptURL = Bundle.module.url(forResource: "Load257Tiles", withExtension: "script") else {
            XCTFail("Missing required test file \"Load257Tiles.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.imageTooComplex = error else {
                XCTFail("Returned error should be .imageTooComplex")
                return
            }
        }
    }

    // MARK: Offset
    
    // Verify that a script containing just an offset:0:0
    // command returns a 1-frame video at 0,0
    func testOffset00() throws {
        guard let scriptURL = Bundle.module.url(forResource: "Offset00", withExtension: "script") else {
            XCTFail("Missing required test file \"Offset00.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        // Verify that the properties match what is expected from the script
        XCTAssert(video.frames.count == 1)
        XCTAssert(video.frames[0].xOffset == 0)
        XCTAssert(video.frames[0].yOffset == 0)
    }

    func testOffsetNonNumericArguments() throws {
        guard let scriptURL = Bundle.module.url(forResource: "OffsetNonNumericArguments", withExtension: "script") else {
            XCTFail("Missing required test file \"OffsetNonNumericArguments.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.badArguments = error else {
                XCTFail("Returned error should be .badArguments")
                return
            }
        }
    }
    
    // MARK: Pause

    // Verify that a script that contains just the command
    // pause:1 creates a 1 frame video displaying a blank
    // screen.
    func testPause1() throws {
        guard let scriptURL = Bundle.module.url(forResource: "Pause1", withExtension: "script") else {
            XCTFail("Missing required test file \"Pause1.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        // Verify that the properties match what is expected from the script
        XCTAssert(video.frames.count == 1)
        XCTAssert(video.frames[0].xOffset == 0)
        XCTAssert(video.frames[0].yOffset == 0)
    }
    
    func testPauseMax() throws {
        guard let scriptURL = Bundle.module.url(forResource: "PauseMax", withExtension: "script") else {
            XCTFail("Missing required test file \"Pause1.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        // Verify that the properties match what is expected from the script
        XCTAssert(video.frames.count == UInt16.max)
        XCTAssert(video.frames[0].xOffset == 0)
        XCTAssert(video.frames[0].yOffset == 0)

    }

    func testPause0() throws {
        guard let scriptURL = Bundle.module.url(forResource: "Pause0", withExtension: "script") else {
            XCTFail("Missing required test file \"Pause0.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.invalidDelayValue = error else {
                XCTFail("Returned error should be .invalidDelayValue(offset,_)")
                return
            }
        }
    }

    func testPause16BitOverflow() throws {
        guard let scriptURL = Bundle.module.url(forResource: "Pause16BitOverflow", withExtension: "script") else {
            XCTFail("Missing required test file \"Pause16BitOverflow.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.invalidDelayValue = error else {
                XCTFail("Returned error should be .invalidDelayValue")
                return
            }
        }
    }
    
    func testPauseBadArgument() throws {
        guard let scriptURL = Bundle.module.url(forResource: "PauseBadArgument", withExtension: "script") else {
            XCTFail("Missing required test file \"PauseBadArgument.script\"")
            return
        }
        XCTAssertThrowsError(try SynthVideo(script: scriptURL)) { error in
            guard case SynthVideoScriptError.badArguments = error else {
                XCTFail("Returned error should be .badArguments")
                return
            }
        }
    }
}
