import XCTest
@testable import SynthVideo

final class SynthVideoTests: XCTestCase {
    /*
     This suite of tests verifies that the commands
     used in the scripting language to initialize
     SynthVideo instances function as expected.
     The tests verify:
        * An empty file, a file consisting only of
        comments, or a file with text that can not
        be interpreted as a script command
        throw an error
     * The ActiveBlack and ActiveWhite commands do not take arguments
     
        
     */
    func testScriptCommands() throws {
        // These bundled .script files each have an error that will cause
        // the script initializer to throw an error.
        let throwingScripts = [
            // No script commands
            "EmptyFile", "PlainText", "OnlyComments",

            // ActiveWhite/ActiveBlack
            "ActiveBlackArguments", "ActiveWhiteArguments",

            // Load errors
            "LoadMissingFile", "LoadInvalidImageFile", "LoadWideImage", "LoadTallImage", "LoadComplexImage",
            
            // Pause errors
            "Pause16BitOverflow", "Pause0",
            
            // Offset
            "OffsetNonNumericArguments"
            ]
        
        for throwingScript in throwingScripts {
            // Ensure that the needed script resources are available in the package.
            guard let scriptURL = Bundle.module.url(forResource: throwingScript, withExtension: "script") else {
                XCTFail("Missing required test file \"\(throwingScript).script\"")
                return
            }
            XCTAssertThrowsError(try SynthVideo(script: scriptURL))
        }
        
        // These scripts test the various script functions,
        // and return a valid SynthVideo object
        let validScripts = [
            // ActiveBlack/ActiveWhite
            "ActiveBlack", "ActiveWhite",
            // Load
            "LoadMaxTiles",
            
            // Pause
            "Pause1", "PauseMax",
            
            // Offset
            "Offset00"
        ]
        
        for validScript in validScripts {
            guard let scriptURL = Bundle.module.url(forResource: validScript, withExtension: "script") else {
                XCTFail("Missing required test file \"\(validScript).script\"")
                return
            }
            XCTAssertNoThrow(try SynthVideo(script: scriptURL))
        }
        
    }

    func loadTextfile(filename: String, ext: String) -> String? {
        guard let textUrl = Bundle.module.url(forResource: filename, withExtension: ext) else {
            return nil
        }
        do {
            return try String(contentsOf: textUrl)
        } catch {
            return nil
        }
    }
}
