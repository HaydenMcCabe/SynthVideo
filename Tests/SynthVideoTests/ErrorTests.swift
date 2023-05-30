//
//  ErrorTests.swift
//  
//
//  Created by Hayden McCabe on 5/30/23.
//

import XCTest
@testable import SynthVideo

final class ErrorTests: XCTestCase {

    func testErrorString() {
        for error in SynthVideoError.allCases {
            XCTAssert(!error.localizedDescription.isEmpty)
        }
    }

}
