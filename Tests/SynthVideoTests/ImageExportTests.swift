//
//  ImageExportTests.swift
//  
//
//  Created by Hayden McCabe on 5/23/23.
//

import XCTest
import CoreGraphics
import CoreImage

@testable import SynthVideo

final class ImageExportTests: XCTestCase {

    func testImageExport() throws {
        // Create a multiframe video
        guard let scriptURL = Bundle.module.url(forResource: "ImageExport", withExtension: "script") else {
            XCTFail("Missing required test file \"ImageExport.script\"")
            return
        }
        
        let video = try SynthVideo(script: scriptURL)
        
        // Create a subdirectory of the temp directory to export the frames into
        let subdirectoryName = "ImageExport\(Int.random(in: 1000...9999))"
        let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(subdirectoryName, conformingTo: .directory)
        
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: false)

        // Export the frames into the new subdirectory
        try video.exportImageSequence(outputFolder: exportDirectory, baseFilename: "testframe")
        
        // Verify that the files are all present and correctly sized
        for i in 0 ..< video.frames.count {
            let filename = "testframe_\(i).png"
            
            // Make sure the images can be read as image data
            let fileURL = exportDirectory.appendingPathComponent(filename)
            guard let ciImage = CIImage(contentsOf: fileURL) else {
                XCTFail()
                return
            }
            
            // Make sure the images have the correct dimensions.
            XCTAssert(ciImage.extent.width == 400 && ciImage.extent.height == 300)
        }
        
        // Create a script that loads the newly created images as frames and compare the
        // recreated video to the original
        var testScript = "ActiveWhite\n"
        for i in 0 ..< video.frames.count {
            testScript += "load:testframe_\(i).png:0:0\n"
        }
        let recreatedVideo = try SynthVideo(script: testScript, workingDirectory: exportDirectory)
        
        XCTAssert(video.frames.count == recreatedVideo.frames.count)
        for i in 0 ..< video.frames.count {
            XCTAssert(video.frames[i] == recreatedVideo.frames[i])
        }
        
        // Delete the image subdirectory
        try FileManager.default.removeItem(at: exportDirectory)

    }

    /// Verify that passing an array of colors will create a sequence of images
    /// representing each frame as a different color. The test does not fail when the
    /// colors don't match exactly, as that is expected due to the conversion to/from
    /// PNG format. A summary for the error in color accuracy is provided where available.
    func testMulticolorExport() throws {
        // The number of test iterations,
        // also used to determine the output filenames
        let testCount = 1000
        
        // Create some random colors
        // CGColor uses a floating point value when defining a color
        // channel, but the underlying 24-bit color space of PNG
        // is integer based. Create, and store integer RGB values,
        // convert to floating point for the export stage, and
        // compare to the imported values later.
        var reds = [UInt8]()
        var greens = [UInt8]()
        var blues = [UInt8]()
        var colors = [CGColor]()
        
        for i in 0 ..< testCount {
            reds.append(UInt8.random(in: 0...255))
            greens.append(UInt8.random(in: 0...255))
            blues.append(UInt8.random(in: 0...255))
            
            let floatRed = CGFloat(reds[i])/255
            let floatGreen = CGFloat(greens[i])/255
            let floatBlue = CGFloat(blues[i])/255
            
            colors.append(CGColor(red: floatRed, green: floatGreen, blue: floatBlue, alpha: 1))
        }
        
        // Make a subdirectory of temp to store the output images
        let subdirectoryName = "MulticolorExport\(Int.random(in: 1000...9999))"
        let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(subdirectoryName, conformingTo: .directory)
        
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: false)

        // Create a video with one frame of all active pixels
        // The ActiveWhite test script renders this video.
        guard let scriptURL = Bundle.module.url(forResource: "ActiveBlack", withExtension: "script") else {
            XCTFail("Missing required test file \"ActiveBlack.script\"")
            return
        }

        let video = try SynthVideo(script: scriptURL)
        
        // Render the images into the subdirectory. Each image should be
        // a 400x300 PNG filled with the color.
        try video.exportImageSequence(outputFolder: exportDirectory, baseFilename: "image", colors: colors)
        
        // DEBUG: Find per-channel color accuracy
        var redError = [UInt8]()
        var greenError = [UInt8]()
        var blueError = [UInt8]()
        
        // Load each exported image, and find the
        for i in 0 ..< testCount {
            // The exported filenames are zero-padded so their filenames are all of equal length.
            let numericalPrefix: String = {
                // Find the number of digits required to display the count of colors
                let digitCount = "\(testCount - 1)".count
                return String(format: "_%0\(digitCount)d_", i)
            }()
            let filename = "image" + numericalPrefix + "0.png"
            let imageURL = exportDirectory.appendingPathComponent(filename)
            
            // Load the PNG image data as a CIImage
            guard let ciImage = CIImage(contentsOf: imageURL) else {
                XCTFail()
                return
            }
            
            // Verify the dimensions are 400x300
            XCTAssert(ciImage.extent.width == 400 && ciImage.extent.height == 300)
            
            // Render the CIImage data into a CGImage
            guard let cgImage = CIContext().createCGImage(ciImage, from: CGRect(origin: CGPointMake(0, 0), size: CGSize(width: 400, height: 300))) else {
                throw SynthVideoError.graphicConversionError
            }

            // Establish a 4-byte buffer to store the channels of the test pixel
            let rawPixelBuffer = UnsafeMutableRawPointer.allocate(byteCount: 4, alignment: 4)
            defer {
                rawPixelBuffer.deallocate()
            }
            // Set up a typed pointer
            let pixelBuffer = rawPixelBuffer.bindMemory(to: UInt8.self, capacity: 4)

            // Get a reference to the rendered CGImage
            guard let pixelData = cgImage.dataProvider?.data else {
                XCTFail()
                return
            }
            
            // Sample the first pixel
            CFDataGetBytes(pixelData, CFRange(location: 0, length: 4), pixelBuffer)
            
            // Copy the channel information
            let sampledRed = pixelBuffer[0]
            let sampledGreen = pixelBuffer[1]
            let sampledBlue = pixelBuffer[2]
            let sampledAlpha = pixelBuffer[3]
            
            // The conversion to a floating point representation of the color channel value,
            // as well as the conversion to/from PNG will have altered the color values
            // from the originals. Test that the sampled values fall into an acceptable range
            // for each channel.
            // Green values tend to vary significantly more than red or blue.
            let redMargin = 35
            let greenMargin = 65
            let blueMargin = 35
            
            // Some notably verbose code is required to prevent underflow/overflow issues
            // with unsigned integers
            let redMin = UInt8(max(Int(reds[i]) - redMargin,0))
            let redMax = UInt8(min(Int(reds[i]) + redMargin,255))
            let greenMin = UInt8(max(Int(greens[i]) - greenMargin,0))
            let greenMax = UInt8(min(Int(greens[i]) + greenMargin,255))
            let blueMin = UInt8(max(Int(blues[i]) - blueMargin,0))
            let blueMax = UInt8(min(Int(blues[i]) + blueMargin,255))

            // Verify that the sampled colors are within the acceptable range
            XCTAssert((redMin...redMax).contains(sampledRed))
            XCTAssert((greenMin...greenMax).contains(sampledGreen))
            XCTAssert((blueMin...blueMax).contains(sampledBlue))
            
            // Alpha should always be 255
            XCTAssert(sampledAlpha == 255)
            
            // Store error information to print later
            if sampledRed > reds[i] {
                redError.append(sampledRed - reds[i])
            } else {
                redError.append(reds[i] - sampledRed)
            }
            if sampledGreen > greens[i] {
                greenError.append(sampledGreen - greens[i])
            } else {
                greenError.append(greens[i] - sampledGreen)
            }
            if sampledBlue > blues[i] {
                blueError.append(sampledBlue - blues[i])
            } else {
                blueError.append(blues[i] - sampledBlue)
            }
        }
        
        print("--- Image Sequence Export ---")
        print("Max color channel error:")
        print("Red: \(redError.sorted().last!)")
        print("Green: \(greenError.sorted().last!)")
        print("Blue: \(blueError.sorted().last!)\n")
        
        let redAvgError = Double(redError.map({Int($0)}).reduce(0, +))/Double(testCount)
        let greenAvgError = Double(greenError.map({Int($0)}).reduce(0, +))/Double(testCount)
        let blueAvgError = Double(blueError.map({Int($0)}).reduce(0, +))/Double(testCount)
        print("Average color channel error:")
        print("Red: \(redAvgError)")
        print("Green: \(greenAvgError)")
        print("Blue: \(blueAvgError)\n")
        
        // Delete the subdirectory
        do {
            try FileManager.default.removeItem(at: exportDirectory)
        } catch {
            XCTFail()
            return
        }
        
        
    }
    
}
