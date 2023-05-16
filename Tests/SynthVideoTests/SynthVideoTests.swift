import XCTest
@testable import SynthVideo

final class SynthVideoTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        //XCTAssertEqual(SynthVideo().text, "Hello, World!")
        let testDataUrl = URL(string: "replace")!
        let video = try! SynthVideo(script: testDataUrl)
        
    }
}
