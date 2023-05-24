//
//  SynthVideo+exportImageSequence.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 4/6/23.
//

import CoreGraphics
import CoreImage
import Foundation

extension SynthVideo {
    public func exportImageSequence(outputFolder: URL, baseFilename: String, colors: [CGColor] = [CGColor(red: 1, green: 1, blue: 1, alpha: 1)]) throws {
        // Verify that the given URL is a folder
        guard (try! outputFolder.resourceValues(forKeys: [.isDirectoryKey])).isDirectory ?? false else {
            throw SynthVideoError.fileNotFound(filename: outputFolder.absoluteString, lineNumber: 0)
        }
        
        guard !colors.isEmpty else {
            throw SynthVideoError.graphicConversionError
        }
        
        // The CGContext is used to color the frame
        let cgContext = CGContext(data: nil,
                                  width: 400,
                                  height: 300,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.genericRGBLinear)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        
        // The CIContext is used to export the data to PNG format
        let ciContext = CIContext()
        
        for i in 0 ..< colors.count {
            cgContext.setFillColor(colors[i])
            // Create a string that will keep the image names in order
            // when rendering for multiple colors, or is blank if only one color is selected
            let numericalPrefix: String = {
                if colors.count == 1 {
                    return ""
                }
                // Find the number of digits required to display the count of colors
                let digitCount = "\(colors.count - 1)".count
                return String(format: "_%0\(digitCount)d", i)
            }()
            
            for frameNumber in (0 ..< frames.count) {
                let digitCount = "\(frames.count - 1)".count
                let frameNumberString = String(format: "%0\(digitCount)d", frameNumber)
                let filename = baseFilename + numericalPrefix + "_" + frameNumberString + ".png"
                
                let fileUrl = outputFolder.appending(path: filename)
                
                let uncolorizedImage = imageForFrame(frameNumber)!
                cgContext.setBlendMode(.normal)
                cgContext.fill(rect)
                // Multiply the bitmap to yield a colored image.
                cgContext.setBlendMode(.multiply)
                cgContext.draw(uncolorizedImage, in: rect)
                cgContext.flush()
                
                guard let cgImage = cgContext.makeImage() else {
                    throw SynthVideoError.graphicConversionError
                }
                
                let ciImage = CIImage(cgImage: cgImage)
                let pngData = ciContext.pngRepresentation(of: ciImage, format: .BGRA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                if let pngData {
                    do {
                        try pngData.write(to: fileUrl)
                    } catch {
                        throw SynthVideoError.outputFileUnavailable
                    }
                    
                } else {
                    throw SynthVideoError.graphicConversionError
                }
            }
            
        }
        
        
        
    }
}
