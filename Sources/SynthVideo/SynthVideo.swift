//
//  SynthVideo.swift
//  VideoConversion
//
//  Created by Hayden McCabe on 12/22/22.
//

import AVFoundation
import CoreVideo
import CoreImage
import Foundation

public struct SynthVideo {
    // MARK: Public types
    public let frames: [Screen]
    
    private let bitmapCache = NSCache<Screen, CGImage>()
    
    private var framesForScreen: [Screen : [Int]] = [Screen.blank : []]
    
    // MARK: Initializers
    
    
    /// Initialize from the ROM data used in the synthesizer
    ///
    /// - Parameter romFile: The URL of a video ROM data file to load
    ///
    /// - Throws: `SynthVideoError.fileCorruption`
    /// when the file can not be interpreted as ROM data.
    ///
    public init(romFile: URL) throws {
        let romData = try Data(contentsOf: romFile)
        try self.init(romData: romData)
    }
    
    /// Initialize from the ROM data used in the synthesizer
    ///
    /// - Parameter romData: A Data instance containing the ROM
    ///
    /// - Throws: `SynthVideoError.fileCorruption`
    /// when the file can not be interpreted as ROM data.
    public init(romData: Data) throws {
        // Variables to build up the data for the SynthVideo struct
        var timeline = [TimelineElement]()
        var frames = [Screen]()

        // Track what the current screen looks like
        // so it can be added to the `frames` array
        var currentScreen = Screen.blank
        
        // Set up memory structures to emulate the video hardware
        
        // Allocate RAM
        let tileLibraryRam = UnsafeMutableRawPointer.allocate(byteCount: 256*12, alignment: 4)
        defer {
            tileLibraryRam.deallocate()
        }
        
        // Create typed pointers to the memory block
        let tileLibraryPtr8 = tileLibraryRam.bindMemory(to: UInt8.self, capacity: 256*12)
        let tileLibraryPtr32 = tileLibraryRam.bindMemory(to: UInt32.self, capacity: 256*3)
        
        // Initialize the memory to all 0s
        for i in 0 ..< 256*3 {
            tileLibraryPtr32[i] = 0
        }
        
        var tileMap = [[UInt8]].init(repeating: [UInt8].init(repeating: 0, count: 100), count: 50)
        var xOffset: UInt16 = 0
        var yOffset: UInt16 = 0
        
        var frameNumber = 0
        
        // Read through the ROM data, and update the tile library and tile map,
        // then record the delay or save the relevant bytes into a screen
        
        // Create a scope where the unsafe bytes of the ROM data
        // are available.
        try romData.withUnsafeBytes() {
            romPtr8 in
            // view the data as 16-bit unsigned Ints
            let romPtr16 = romPtr8.bindMemory(to: UInt16.self)
            let romPtr32 = romPtr8.bindMemory(to: UInt32.self)
            
            var romIndex = romPtr16.startIndex
                        
            // Main run loop
            // Read through the animation ROM, generate each frame,
            // and copy the frame buffers into the asset writer.
            
            // This loop will run once per frame in the output
            // video. It will end once the ROM has been entirely
            // read, or if encountering the 0xBEEFCAFE command.
            romLoop: while romIndex < romPtr16.count {
                // Process the next command in the animation ROM
                // This code emulates the logic of the function
                // FRAME_UPDATE_SWIRQ() in view.c
                
                let word1 = romPtr16[romIndex]
                let word2 = romPtr16[romIndex+1]
                
                // Check for the special cases
                if (word1 == 0xBEEF && word2 == 0xCAFE) {
                    // The 0xBEEFCAFE command resets the animation system
                    // and loops back to the beginning on real hardware. Here
                    // it marks the point to stop making the video
                    break romLoop
                } else if (word1 == 0xBABE) {
                    let delay = word2
                    guard word2 > 0 else {
                        throw SynthVideoError.invalidDelayValue
                    }
                    // The range of frames will extend for the duration of the
                    // delay. The delay includes the frame during which this
                    // event is processed, so the additional delays are (word2 - 1)
                    let range = frameNumber...(frameNumber+Int(delay)-1)
                    timeline.append(.delay(delay: delay, range: range))
                    
                    // var framesForCurrentScreen = framesForScreen[currentScreen]!
                    
                    for _ in 0 ..< delay {
                        frames.append(currentScreen)
                        //framesForCurrentScreen.append(frameNumber)
                        frameNumber += 1
                    }
                    
                    //framesForScreen[currentScreen] = framesForCurrentScreen
                    
                    romIndex += 2
                } else {
                    // This is a frame update command, where
                    // word1 and word2 are the new xOffset and
                    // yOffset, respectively.
                    xOffset = word1
                    yOffset = word2
                    let lib_update_count = romPtr16[romIndex+2]
                    let tile_update_count = romPtr16[romIndex+3]
                    
                    // Check that these values make sense, or throw
                    // an error.
                    guard xOffset < vramPixelColumns,
                          yOffset < vramPixelRows,
                          lib_update_count <= vramTilePositions,
                          tile_update_count <= (vramTileColumns * vramTileRows) else {
                        throw SynthVideoError.fileCorruption
                    }
                    
                    romIndex += 4
                                        
                    for _ in 0..<lib_update_count {
                        // The index in the 32-bit pointer is half of that
                        // in the 16-bit pointer. The 16-bit value should
                        // be even, due to the alignment of the data format.
                        let romIndex32 = romIndex / 2
                        
                        // The update data is read as 4 32-bit words. The first
                        // is the library index to copy into, followed by the
                        // 12 bytes of pixel data.
                        let libraryIndex = romPtr32[romIndex32]
                                                    
                        // From the libraryIndex, find the actual index in the
                        // allocated memory for a 32-bit pointer
                        let libraryIndex32 = Int(libraryIndex * 3)
                        
                        // Copy the values as 32-bit words
                        tileLibraryPtr32[libraryIndex32] = romPtr32[romIndex32 + 1]
                        tileLibraryPtr32[libraryIndex32 + 1] = romPtr32[romIndex32 + 2]
                        tileLibraryPtr32[libraryIndex32 + 2] = romPtr32[romIndex32 + 3]
                        
                        // Advance the index for 8 16-bit values after reading 4 32-bit values
                        romIndex += 8
                    }
                    
                    // Repeat to update the tile map
                    for _ in 0 ..< tile_update_count {
                        // The tile updates come as 16-bit pairs, with the
                        // first value containting the coordinates, and
                        // the second with the value
                        let coordinates = romPtr16[romIndex]
                        let row = Int(coordinates & 0xFF)
                        let col = Int(coordinates >> 8)
                        
                        let value = UInt8(romPtr16[romIndex+1])
                        tileMap[row][col] = value
                        romIndex += 2
                    }
                    
                    // With the memory set, capture the section needed to draw this screen
                    // Make a dictionary of sets to track the tiles seen
                    var screenTiles = TilePositions()
                    
                    let startRow = Int(yOffset / 12)
                    let rowCount = Int((yOffset % 12 == 0) ? 25 : 26)
                    
                    let startCol = Int(xOffset / 8)
                    let colCount = Int((xOffset % 8 == 0) ? 50 : 51)
                    
                    for row in startRow ..< (startRow + rowCount) {
                        for col in startCol ..< (startCol + colCount) {
                            let tileMapRow = row % 50
                            let tileMapCol = col % 100
                            // For each tile on screen, retrieve its tile index
                            // and read the bytes of that tile from the library.
                            let tileIndex = Int(tileMap[tileMapRow][tileMapCol])
                            let libraryIndexStart = tileIndex * 12
                            
                            let tile = {
                                var pixels = [UInt8]()
                                for i in 0 ..< 12 {
                                    pixels.append(tileLibraryPtr8[libraryIndexStart + i])
                                }
                                return try! Tile(pixels: pixels)
                            }()
                                        
                            screenTiles.add(key: tile, position: TileMapPosition(row: UInt8(tileMapRow), col: UInt8(tileMapCol)))
                        }
                    }
                    
                    
                    let range = frameNumber...frameNumber
                    currentScreen = Screen(tilePositions: screenTiles, xOffset: xOffset, yOffset: yOffset)
                    frames.append(currentScreen)
                    timeline.append(.screen(screen: currentScreen, range: range))
                    // framesForScreen[currentScreen] = [frameNumber]
                    
                    frameNumber += 1
                }
            }
        }
        
        self.timeline = timeline
        self.frames = frames
    }
    
    /// Initialize from a script file.
    ///
    /// - Parameter script: The URL of a video script file. All
    /// file references in the script will be interpreted in reference to the
    /// enclosing folder of the script file.
    ///
    ///
    /// - Throws: `SynthVideoError.fileNotFound`
    ///
    /// `SynthVideoError.permissionError`
    ///
    /// `SynthVideoError.badArguments`
    ///
    /// `SynthVideoError.unableToLoadImage`
    ///
    /// `SynthVideoError.imageTooComplex`
    ///
    /// `SynthVideoError.invalidDelayValue`
    ///
    /// `SynthVideoError.unknownCommand`
    public init(script: URL) throws {
        let scriptString = try String(contentsOf: script)
        let directoryPath = script.pathComponents.dropLast(1).joined(separator: "/")
        let workingDirectory = URL(filePath: directoryPath)
        try self.init(script: scriptString, workingDirectory: workingDirectory)
    }
    
    /// Initialize from a script in String format.
    ///
    /// - Parameter script: A string containing a video initialization script
    ///
    /// - Parameter workingDirectory: The directory to use when finding the absolute URLs of relative URLs in the script
    ///
    /// - Throws: `SynthVideoError.fileNotFound`
    ///
    /// `SynthVideoError.permissionError`
    ///
    /// `SynthVideoError.badArguments`
    ///
    /// `SynthVideoError.unableToLoadImage`
    ///
    /// `SynthVideoError.imageTooComplex`
    ///
    /// `SynthVideoError.invalidDelayValue`
    ///
    /// `SynthVideoError.unknownCommand`
    public init(script: String, workingDirectory: URL) throws {
        // Verify that the input file is readable
        // as UTF8 text, then break it into an
        // array of lines and filter out comments.
        let scriptLines = script.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                return String(line.split(separator: "#", omittingEmptySubsequences: false)
                    .first?.trimmingCharacters(in: .whitespaces) ?? "")
            }
        
        // Verify that the given working directory is
        // indeed a directory and that the user has read
        // permissions for it.
        let workingDirectory = try {
            let directoryPath = workingDirectory.path()
            // Check that the path is indeed a directory
            var isDirectory = ObjCBool(false)
            let exists = FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory)

            let isReadable = FileManager.default.isReadableFile(atPath: directoryPath)

            guard isDirectory.boolValue, exists, isReadable else {
                throw SynthVideoError.permissionError
            }
            return URL(fileURLWithPath: directoryPath)
        }()

        // The last image loaded from a file, represented as UInt8 arrays. The default value is a blank 50x25 tile (400 x 300 pixel) screen
        var imageTiles = {
            let blankRow = Array(repeating: Tile.blank, count: 50)
            return Array(repeating: blankRow, count: 25)
        }()
        
        // The last screen seen, defaulting to a blank screen
        
        var screen = Screen.blank

        // A working copy of timeline and frames
        var timeline = [TimelineElement]()
        var frames = [Screen]()
        
        // The color that is currently used to determine if a pixel is on
        // This can be changed by the `activeBlack` and `activeWhite`
        // script commands
        var activeBlack = true
                
        for (lineNumber, line) in scriptLines.enumerated() {
            // Get the actual line of the text file
            // being considered in case an error is thrown.
            let lineNumber = lineNumber + 1
            
            // Ignore blank lines
            if line == "" {
                continue
            }
            
            let components = line.split(separator: ":")
            switch components[0].trimmingCharacters(in: .whitespaces).lowercased() {
            case "activeblack":
                // Ensure the arguments are given as UInt values, then convert them to CGFloat
                guard components.count == 1 else {
                    throw SynthVideoError.badArguments(command: "ActiveBlack", lineNumber: lineNumber)
                }
                // Update the color selection
                activeBlack = true
            case "activewhite":
                guard components.count == 1 else {
                    throw SynthVideoError.badArguments(command: "ActiveWhite", lineNumber: lineNumber)
                }
                activeBlack = false
            case "load":
                // Make a URL for the filename relative to the working directory
                guard
                    components.count == 4,
                    let xOffset = Int(components[2]), xOffset >= 0,
                    let yOffset = Int(components[3]), yOffset >= 0
                else {
                    throw SynthVideoError.badArguments(command: "load", lineNumber: lineNumber)
                }

                // Load the image file as an array of tiles
                imageTiles = try {
                    let filename = components[1].trimmingCharacters(in: .whitespaces)
                    do {
                        guard let imageURL = URL(string: filename, relativeTo: workingDirectory)
                        else {
                            throw SynthVideoError.unableToLoadImage(fileName: String(components[1]), lineNumber: lineNumber)
                        }

                        return try SynthVideo.loadImage(url: imageURL, activeBlack: activeBlack)
                    } catch {
                        if case SynthVideoError.incorrectImageDimensions = error {
                            throw SynthVideoError.incorrectImageDimensions
                        } else {
                            throw SynthVideoError.unableToLoadImage(fileName: filename, lineNumber: lineNumber)
                        }
                    }
                }()
                
                let tileSet = SynthVideo.tilesForFrame(in: imageTiles, x: xOffset, y: yOffset)

                if tileSet.count > 256 {
                    throw SynthVideoError.imageTooComplex
                }
                
                // Create and save a screen object
                screen = Screen(tilePositions: tileSet, xOffset: UInt16(xOffset % vramPixelColumns), yOffset: UInt16(yOffset % vramPixelRows))
                // `frames` has not yet been updated, so
                // `frames.count` will be the index of this frame
                timeline.append(TimelineElement.screen(screen: screen, range: frames.count...frames.count))
                frames.append(screen)
                
            case "pause":
                // The file format allows for 16-bit delay values
                guard components.count == 2,
                      let delay = UInt16(components[1].trimmingCharacters(in: .whitespaces))
                else {
                    throw SynthVideoError.badArguments(command: "pause", lineNumber: lineNumber)
                }
                guard delay > 0 else {
                    throw SynthVideoError.invalidDelayValue
                }
                
                // Update the timeline with the existing
                // screen for `delay` frames.
                timeline.append(TimelineElement.delay(delay: delay, range: frames.count...(frames.count + Int(delay) - 1)))
                for _ in 0 ..< delay {
                    frames.append(screen)
                }
                
            case "offset":
                guard components.count == 3,
                      let xOffset = Int(components[1].trimmingCharacters(in: .whitespaces)),
                      let yOffset = Int(components[2].trimmingCharacters(in: .whitespaces))
                else {
                    throw SynthVideoError.badArguments(command: "offset", lineNumber: lineNumber)
                }

                let tileSet = SynthVideo.tilesForFrame(in: imageTiles, x: xOffset, y: yOffset)
                screen = Screen(tilePositions: tileSet, xOffset: UInt16(xOffset % vramPixelColumns), yOffset: UInt16(yOffset % vramPixelRows))
                timeline.append(TimelineElement.screen(screen: screen, range: frames.count...frames.count))
                frames.append(screen)
            default:
                throw SynthVideoError.unknownCommand(lineNumber: lineNumber)
            }
        }
        
        // Fail to initialize if there are no frames in the resulting video
        if frames.count == 0 {
            throw SynthVideoError.emptyVideo
        }
        
        self.timeline = timeline
        self.frames = frames
    }
    
    // MARK: Private properties
    private let timeline: [TimelineElement]
    
    
    // MARK: Public properties
    public func screenForFrame(_ frame: Int) -> Screen? {
        guard timeline.count > 0, frame >= 0, frame < frames.count else {
            return nil
        }
        
        return frames[frame]
    }
    
    public func imageForFrame(_ frame: Int) -> CGImage? {
        guard let screen = screenForFrame(frame) else {
            return nil
        }
        
        // Return a cached version of the bitmap if available
        if let cached = bitmapCache.object(forKey: screen) {
            return cached
        } else {
            do {
                let image = try cacheFrame(frame)
                return image
            } catch {
                return nil
            }
        }
    }
    
    /// Ensure that a frame is loaded into the cache, rendering it if needed
    @discardableResult public func cacheFrame(_ frame: Int) throws -> CGImage {
        guard let screen = screenForFrame(frame) else {
            throw SynthVideoError.invalidFrameNumber
        }
        
        // Return a cached version of the bitmap if available
        if let cached = bitmapCache.object(forKey: screen) {
            return cached
        }
        
        let tileRows = screen.yOffset % 12 == 0 ? 25 : 26
        let tileColumns = screen.xOffset % 8 == 0 ? 50 : 51
        
        let bitmapHeight = tileRows * 12
        let bitmapWidth = tileColumns * 8
        
        let firstScreenRow = UInt8(screen.yOffset / 12)
        let firstScreenColumn = UInt8(screen.xOffset / 8)
        
        // Make a context in which to render all of the pixels
        let cgContext = CGContext(data: nil, width: bitmapWidth, height: bitmapHeight, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace.init(name: CGColorSpace.genericRGBLinear)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        // Draw the tiles into the context
        for (tile, positions) in screen.tilePositions {
            let tileBitmap = try! SynthVideo.tileBitmap(for: tile)
            for position in positions {
                // Convert a position in the tilemap to a position in the
                // bitmap context.
                let bitmapRow = (position.row < firstScreenRow) ? (position.row + 50 - firstScreenRow) : (position.row - firstScreenRow)
                let bitmapCol = (position.col < firstScreenColumn) ? (position.col + 100 - firstScreenColumn) : (position.col - firstScreenColumn)
                // This positions needs to be converted to a point in the CGContext.
                // First the lower left corner of the tile positions is converted into pixels,
                // then converted to a position assuming a lower left origin.
                let x = Int(bitmapCol) * 8
                let y = bitmapHeight - (Int(bitmapRow) * 12 + 12)
                // Paste the tile into the canvas
                cgContext.draw(tileBitmap, in: CGRect(x: x, y: y, width: 8, height: 12))
            }
        }
        // Make an image from the context
        let fullScreenBitmap = cgContext.makeImage()!
        // Crop the image to the needed size
        let cropX = Int(screen.xOffset % 8)
        let cropY = (Int(screen.yOffset % 12)) % 12
        
        guard let bitmap = fullScreenBitmap.cropping(to: CGRect(x: cropX, y: cropY, width: 400, height: 300)) else {
            fatalError()
        }
        
        // Save this bitmap to the cache
        bitmapCache.setObject(bitmap, forKey: screen)
        
        return bitmap
    }

    /// Export to a standard video file.
    ///
    /// - Parameter url: The URL for the file to be exported. If there is an existing file at this location, it will be deleted.
    /// - Parameter range: An integer range of the frames of the video to be exported. The default range exports the entire video.
    /// - Parameter codec: The codec used to compress the video. The supported codecs are .h264, .hevc, and .jpeg
    ///
    /// - Throws: `SynthVideoError.outputFileUnavailable`
    ///
    /// `SynthVideoError.invalidRange`
    ///
    /// `SynthVideoError.videoInitializationError`
    ///
    /// `SynthVideoError.unsupportedCodec`
    ///
    public func exportVideo(url: URL, range optionalRange: ClosedRange<Int>? = nil , codec: AVVideoCodecType = .h264, color: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)) throws {
        // Verify that the range exists, and is valid for the number
        // of frames in the video, or default to a range for the entire video
        let range = optionalRange ?? (0...(frames.count-1))
        guard let start = range.first, let end = range.last,
              start >= 0, start < frames.count, end < frames.count else {
            throw SynthVideoError.invalidRange
        }
        
        // If there is an existing file at the output URL, delete it
        do {
            if FileManager.default.fileExists(atPath: url.relativePath) {
            //if try url.checkPromisedItemIsReachable() {
                    try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Could not remove file \(error.localizedDescription)")
        }
        
        // Check that the selected codec is supported.
        guard codec == .h264 || codec == .hevc || codec == .jpeg else {
            throw SynthVideoError.unsupportedCodec
        }
        
        let assetWriter: AVAssetWriter = try {
            do {
                return try AVAssetWriter(outputURL: url, fileType: .mp4)
            } catch {
                throw SynthVideoError.outputFileUnavailable
            }
        }()
        
        let assetWriterInput: AVAssetWriterInput
        switch(codec) {
        case .h264:
            let compressionSettings = [AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                       AVVideoAverageBitRateKey: 1_000_000,
                                       AVVideoMaxKeyFrameIntervalKey: 1] as [String : Any]
            assetWriterInput = {
                let assetWriterSettings = [AVVideoCodecKey: codec, AVVideoWidthKey : 400, AVVideoHeightKey: 300, AVVideoCompressionPropertiesKey: compressionSettings] as [String : Any]
                return AVAssetWriterInput.init(mediaType: .video, outputSettings: assetWriterSettings)
            }()
        case .hevc:
            assetWriterInput = {
                let assetWriterSettings = [AVVideoCodecKey: codec, AVVideoWidthKey : 400, AVVideoHeightKey: 300] as [String : Any]
                return AVAssetWriterInput.init(mediaType: .video, outputSettings: assetWriterSettings)
            }()
        case .jpeg:
            let compressionSettings = [AVVideoQualityKey: 1.0] as [String : Any]
            assetWriterInput = {
                let assetWriterSettings = [AVVideoCodecKey: codec, AVVideoWidthKey : 400, AVVideoHeightKey: 300, AVVideoCompressionPropertiesKey: compressionSettings] as [String : Any]
                return AVAssetWriterInput.init(mediaType: .video, outputSettings: assetWriterSettings)
            }()
        default:
            return
        }
        
        let pixelBuffer = try {
            // Make the pixel buffer to render into
            let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                 kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
            var pixelBuffer : CVPixelBuffer? = nil
            // Works with BGRA
            CVPixelBufferCreate(kCFAllocatorDefault, 400, 300, kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)

            guard let pixelBuffer else {
                throw SynthVideoError.videoInitializationError
            }
            return pixelBuffer
        }()
        
        // Lock the pixelBuffer
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        // Create a CGContext that draws into the pixel buffer
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                    width: 400,
                                    height: 300,
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                    space: CGColorSpace(name: CGColorSpace.genericRGBLinear)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)
        assetWriter.add(assetWriterInput)

        
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        
        // Use the existing CGContext to do a multiply
        // blend to colorize each frame, then store them into an array
        context.setFillColor(color)
        var colorizedFrames = [CGImage]()
        for frameNumber in range {
            let uncolorizedImage = imageForFrame(frameNumber)!
            // Paint the canvas with the color.
            context.setBlendMode(.normal)
            context.fill(rect)
            // Multiply the bitmap to yield a colored image.
            context.setBlendMode(.multiply)
            context.draw(uncolorizedImage, in: rect)
            context.flush()
            // Save the results
            let colorizedFrame = context.makeImage()!
            colorizedFrames.append(colorizedFrame)
        }
                
        // Prepare for writing the video
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)

        context.setBlendMode(.normal)
        for (frameNumber, image) in colorizedFrames.enumerated() {
            
            let frameTime = CMTimeMake(value: Int64(frameNumber), timescale: Int32(30))
            // Find the cgImage for this frame
            //let cgImage = imageForFrame(frameNumber)!
            context.draw(image, in: rect)
            context.flush()
            
            while (!assetWriterInput.isReadyForMoreMediaData) { }
            assetWriterAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
        }
        
        print("Writing file")
        assetWriterInput.markAsFinished()
        assetWriter.finishWriting {
            print("Finished writing video")
        }

    }
    
    // MARK: Private utility functions
    private static func loadImage(url: URL, activeBlack: Bool) throws -> [[Tile]] {
        guard let ciImage = CIImage(contentsOf: url) else {
            throw SynthVideoError.unableToLoadImage(fileName: "", lineNumber: 0)
        }
        // Verify the dimensions of the image are correct
        guard let width = ciImage.properties["PixelWidth"] as? Int,
              let height = ciImage.properties["PixelHeight"] as? Int,
              width > 0 && width % 400 == 0,
              height > 0 && height % 300 == 0
        else {
            throw SynthVideoError.incorrectImageDimensions
        }

        guard let cgImage = CIContext().createCGImage(ciImage, from: CGRect(origin: CGPointMake(0, 0), size: CGSize(width: width, height: height))) else {
            throw SynthVideoError.graphicConversionError
        }

        // Get a reference to the bitmap memory layout of the image
        guard let bitmap = cgImage.dataProvider?.data else {
            throw SynthVideoError.graphicConversionError
        }

        // Establish a 4-byte buffer to store the channels of each pixel
        let rawPixelBuffer = UnsafeMutableRawPointer.allocate(byteCount: 4, alignment: 4)
        defer {
            rawPixelBuffer.deallocate()
        }
        // Set up a typed pointer
        let pixelBuffer = rawPixelBuffer.bindMemory(to: UInt8.self, capacity: 4)

        let rows = height / 12
        let cols = width / 8

        // Create the array to be returned
        
        var tileMap = {
            let blankRow = Array<Tile>(repeating: Tile.blank, count: cols)
            return Array<[Tile]>(repeating: blankRow, count: rows)
        }()
        
        // Choose the values to evaluate pixels with.
        let colorComponents: [UInt8] = activeBlack ? [0,0,0,255] : [255,255,255,255]

        for row in 0 ..< rows {
            let pixelRowStart = row * 12
            let pixelRowEnd = pixelRowStart + 12
            for col in 0 ..< cols {
                let pixelColStart = col * 8

                var tileBytes = [UInt8]()

                // Iterate over the individual pixels
                for pixelRow in pixelRowStart ..< pixelRowEnd {
                    // Use a 0 -> 7 index to calculate the column number
                    // so it may be used for bit shifting operations
                    var rowByte: UInt8 = 0
                    for i in 0 ..< 8 {
                        let pixelCol = pixelColStart + i
                        let pixelIndex = (pixelRow * cgImage.bytesPerRow) + (pixelCol * cgImage.bitsPerPixel / 8)
                        // Look at this pixel
                        CFDataGetBytes(bitmap, CFRange(location: pixelIndex, length: 4), pixelBuffer)

                        
                        let pixelOn = (pixelBuffer[0] == colorComponents[0] &&
                                       pixelBuffer[1] == colorComponents[1] &&
                                       pixelBuffer[2] == colorComponents[2] &&
                                       pixelBuffer[3] == colorComponents[3])
                        if pixelOn {
                            rowByte |= 1 << (7 - i)
                        }
                    }
                    tileBytes.append(rowByte)
                }

                tileMap[row][col] = try! Tile(pixels: tileBytes)
            }
        }

        return tileMap
    }
    
    private static func tileBitmap(for tile: Tile) throws -> CGImage {
        // Create a data object to hold 32-bit pixel data for an 8 x 12 tile
        var bitmapData = Data(count: 8 * 12 * 4)
        bitmapData.withUnsafeMutableBytes { ptr8 in
            let ptr32 = ptr8.bindMemory(to: UInt32.self)
            var index32 = 0
            for i in 0 ..< 12 {
                for j in (0 ..< 8).reversed() {
                    // BLUE : GREEN : RED : ALPHA
                    let pixelBit = (try! tile.pixelRow(i) >> j) & 0x01
                    if pixelBit == 0x01 {
                        ptr32[index32] = 0xFFFFFFFF
                    } else {
                        ptr32[index32] = 0x000000FF
                    }
                    index32 += 1
                }
            }
        }
        
        let ciImage = CIImage(bitmapData: bitmapData, bytesPerRow: 32, size: CGSize(width: 8, height: 12), format: .ARGB8, colorSpace: nil)
        
        if let cgImage = CIContext().createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: 8, height: 12)) {
            return cgImage
        } else {
            throw SynthVideoError.graphicConversionError
        }
    }
    
    /// For a given tile bitmap and x and y offsets in imagespace, return a dictionary of tiles and their respective positions
    /// in memoryspace.
    public static func tilesForFrame(in image: [[Tile]], x: Int, y: Int) -> TilePositions {
        // Calculate the range of tiles on-screen for the given x and y
        // This range may exceed the actual bounds of the given array, so
        // modulo operations are used later to ensure correct operation.
        let startRow = y / 12
        let endRow = startRow + (y % 12 == 0 ? 24 : 25)
        let startCol = x / 8
        let endCol = startCol + (x % 8 == 0 ? 49 : 50)

        let imageHeight = image.count // The number of total rows in the image
        let imageWidth = image[0].count // the number of columns in the image

        var tiles = TilePositions()

        for row in startRow...endRow {
            for col in startCol...endCol {
                let tile = image[row % imageHeight][col % imageWidth]
                tiles.add(key: tile, position: TileMapPosition(row: UInt8(row % 50), col: UInt8(col % 100)))
            }
        }

        return tiles
    }
}
