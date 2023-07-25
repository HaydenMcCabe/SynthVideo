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

public class SynthVideo {
    // MARK: Public properties
    public let frames: [Screen]
    
    
    // MARK: Private properties
    private let bitmapCache = NSCache<Screen, CGImage>()
    private var _synthVid: Data? = nil
    
    // MARK: Initializers
    
    /// Initialize from a file containing .synthvid data
    ///
    /// - Parameter romFile: The URL of a video ROM data file to load
    ///
    /// - Throws: `SynthVideoError.fileCorruption`
    /// when the file can not be interpreted as ROM data.
    ///
    public convenience init(synthvidFile: URL) throws {
        let synthvidData = try Data(contentsOf: synthvidFile)
        try self.init(synthvidData: synthvidData)
    }
    
    /// Initialize from the a file containing .synthvid data.
    ///
    /// - Parameter romData: A Data instance containing the ROM
    ///
    /// - Throws: `SynthVideoError.fileCorruption`
    /// when the file can not be interpreted as ROM data.
    public init(synthvidData: Data) throws {
        // Create an array to store the screens as they are created.
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
        try synthvidData.withUnsafeBytes() {
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
                        throw SynthVideoError.fileCorruption
                    }
                                        
                    for _ in 0 ..< delay {
                        frames.append(currentScreen)
                        frameNumber += 1
                    }
                                        
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
                                        
                            screenTiles.add(key: tile, position: try! TileMapPosition(row: UInt8(tileMapRow), col: UInt8(tileMapCol)))
                        }
                    }
                    
                    currentScreen = Screen(tilePositions: screenTiles, xOffset: xOffset, yOffset: yOffset)
                    frames.append(currentScreen)
                    
                    frameNumber += 1
                }
            }
        }
        
        self.frames = frames
        
        // The data passed verification as valid synthVid data, so store it
        _synthVid = synthvidData
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
    public convenience init(script: URL) throws {
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

        // A working copy of frames
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
                    throw SynthVideoScriptError.badArguments(lineNumber: lineNumber)
                }
                // Update the color selection
                activeBlack = true
            case "activewhite":
                guard components.count == 1 else {
                    throw SynthVideoScriptError.badArguments(lineNumber: lineNumber)
                }
                activeBlack = false
            case "load":
                // Make a URL for the filename relative to the working directory
                guard
                    components.count == 4,
                    let xOffset = Int(components[2]), xOffset >= 0,
                    let yOffset = Int(components[3]), yOffset >= 0
                else {
                    throw SynthVideoScriptError.badArguments(lineNumber: lineNumber)
                }

                // Load the image file as an array of tiles
                imageTiles = try {
                    let filename = components[1].trimmingCharacters(in: .whitespaces)
                    do {
                        guard let imageURL = URL(string: filename, relativeTo: workingDirectory)
                        else {
                            throw SynthVideoScriptError.unableToLoadImage(lineNumber: lineNumber)
                        }

                        return try SynthVideo.loadImage(url: imageURL, activeBlack: activeBlack)
                    } catch {
                        if case SynthVideoScriptError.incorrectImageDimensions = error {
                            throw SynthVideoScriptError.incorrectImageDimensions(lineNumber: lineNumber)
                        } else {
                            throw SynthVideoScriptError.unableToLoadImage(lineNumber: lineNumber)
                        }
                    }
                }()
                
                let tileSet = SynthVideo.tilesForFrame(in: imageTiles, x: xOffset, y: yOffset)

                if tileSet.count > 256 {
                    throw SynthVideoScriptError.imageTooComplex(lineNumber: lineNumber)
                }
                
                // Create and save a screen object
                screen = Screen(tilePositions: tileSet, xOffset: UInt16(xOffset % vramPixelColumns), yOffset: UInt16(yOffset % vramPixelRows))
                // `frames` has not yet been updated, so
                // `frames.count` will be the index of this frame
                frames.append(screen)
                
            case "pause":
                // The file format allows for 16-bit delay values
                let trimmedArgument = components[1].trimmingCharacters(in: .whitespaces)
                guard components.count == 2,
                      let delay = UInt16(trimmedArgument)
                else {
                    // See if the argument can be interpreted as a numeric value
                    if trimmedArgument.trimmingCharacters(in: .decimalDigits).count == 0 {
                        throw SynthVideoScriptError.invalidDelayValue(lineNumber: lineNumber)
                    } else {
                        throw SynthVideoScriptError.badArguments(lineNumber: lineNumber)
                    }
                }
                guard delay > 0 else {
                    throw SynthVideoScriptError.invalidDelayValue(lineNumber: lineNumber)
                }
                
                // Add the screen to the frames array
                for _ in 0 ..< delay {
                    frames.append(screen)
                }
                
            case "offset":
                guard components.count == 3,
                      let xOffset = Int(components[1].trimmingCharacters(in: .whitespaces)),
                      let yOffset = Int(components[2].trimmingCharacters(in: .whitespaces))
                else {
                    throw SynthVideoScriptError.badArguments(lineNumber: lineNumber)
                }

                let tileSet = SynthVideo.tilesForFrame(in: imageTiles, x: xOffset, y: yOffset)
                screen = Screen(tilePositions: tileSet, xOffset: UInt16(xOffset % vramPixelColumns), yOffset: UInt16(yOffset % vramPixelRows))
                frames.append(screen)
            default:
                throw SynthVideoScriptError.unknownCommand(lineNumber: lineNumber)
            }
        }
        
        // Fail to initialize if there are no frames in the resulting video
        if frames.count == 0 {
            throw SynthVideoError.emptyVideo
        }
        
        self.frames = frames
    }
    
    // MARK: Public properties
    public struct MemoryState {
        public let xOffset: UInt16
        public let yOffset: UInt16
        public let tileMap: Data
        public let tileLibrary: Data
    }
    
    private var _memoryStates: [MemoryState]? = nil
    lazy public var memoryStates: [MemoryState] = {
        if let _memoryStates {
            return _memoryStates
        }
        
        var memoryStates = [MemoryState]()
        
        // Initialize data objects representing
        // the in-memory values. The values
        // in these are saved to the memoryStates
        // array for each frame.
        let tileMapCount = vramTileColumns * vramTileRows
        let tileMapRam = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: tileMapCount)
        for i in 0 ..< tileMapRam.count {
            tileMapRam[i] = 0
        }
        
        let tileLibraryRam = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: 256*3)
        for i in 0 ..< tileLibraryRam.count {
            tileLibraryRam[i] = 0
        }
        
        var xOffsetMemory: UInt16 = 0
        var yOffsetMemory: UInt16 = 0
                
        // Create a synthvid representation
        // and create pointers to the data.
        synthvid.withUnsafeBytes { romPtr8 in
            let romPtr16 = romPtr8.bindMemory(to: UInt16.self)
            let romPtr32 = romPtr8.bindMemory(to: UInt32.self)
            
            var romIndex = 0
            
        romLoop: while romIndex < romPtr16.count {
                // Parse the file to look for the next command
                let word1 = romPtr16[romIndex]
                let word2 = romPtr16[romIndex+1]
                
                if (word1 == 0xBEEF && word2 == 0xCAFE) {
                    // The 0xBEEFCAFE command resets the animation system
                    // and loops back to the beginning on real hardware. Here
                    // it marks the point to stop making the video
                    break romLoop
                } else if (word1 == 0xBABE) {
                    let delay = word2
                    guard word2 > 0 else {
                        // Corrupted data
                        // Invalid delay value
                        fatalError()
                    }
                    
                                        
                    let frameState = MemoryState(xOffset: xOffsetMemory,
                                                 yOffset: yOffsetMemory,
                                                 tileMap: Data(buffer: tileMapRam),
                                                 tileLibrary: Data(buffer: tileLibraryRam))
                    // Append the frame data
                    // for each frame
                    for _ in 0 ..< delay {
                        memoryStates.append(frameState)
                    }
                                        
                    romIndex += 2
                } else {
                    // This is a frame update command, where
                    // word1 and word2 are the new xOffset and
                    // yOffset, respectively.
                    xOffsetMemory = word1
                    yOffsetMemory = word2
                    let lib_update_count = romPtr16[romIndex+2]
                    let tile_update_count = romPtr16[romIndex+3]
                    
                    // Check that these values make sense, or throw
                    // an error.
                    guard xOffsetMemory < vramPixelColumns,
                          yOffsetMemory < vramPixelRows,
                          lib_update_count <= vramTilePositions,
                          tile_update_count <= (vramTileColumns * vramTileRows) else {
                        fatalError()
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
                        tileLibraryRam[libraryIndex32] = romPtr32[romIndex32 + 1]
                        tileLibraryRam[libraryIndex32 + 1] = romPtr32[romIndex32 + 2]
                        tileLibraryRam[libraryIndex32 + 2] = romPtr32[romIndex32 + 3]
                        
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
                        
                        let index = row * vramTileColumns + col
                        
                        let value = UInt8(romPtr16[romIndex+1])
                        tileMapRam[index] = value

                        romIndex += 2
                    }
                    
                    // Create a MemoryState to store the current contents
                    // of the tilemap and tile library and offsets.
                    let frameState = MemoryState(xOffset: xOffsetMemory,
                                                 yOffset: yOffsetMemory,
                                                 tileMap: Data(buffer: tileMapRam),
                                                 tileLibrary: Data(buffer: tileLibraryRam))
                    memoryStates.append(frameState)

                    
                }
                
            }
            
            
        }
                
        return memoryStates
    }()
    
    public func screenForFrame(_ frame: Int) -> Screen? {
        guard frame >= 0, frame < frames.count else {
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
            context.draw(image, in: rect)
            context.flush()
            
            while (!assetWriterInput.isReadyForMoreMediaData) { }
            assetWriterAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
        }
        
        assetWriterInput.markAsFinished()
        assetWriter.finishWriting {}

    }
    
    // MARK: Private utility functions
    private static func loadImage(url: URL, activeBlack: Bool) throws -> [[Tile]] {
        guard let ciImage = CIImage(contentsOf: url) else {
            throw SynthVideoScriptError.unableToLoadImage(lineNumber: 0)
        }
        // Verify the dimensions of the image are correct
        guard let width = ciImage.properties["PixelWidth"] as? Int,
              let height = ciImage.properties["PixelHeight"] as? Int,
              width > 0 && width % 400 == 0,
              height > 0 && height % 300 == 0
        else {
            throw SynthVideoScriptError.incorrectImageDimensions(lineNumber: 0)
        }

        guard let cgImage = CIContext().createCGImage(ciImage, from: CGRect(origin: CGPointMake(0, 0), size: CGSize(width: width, height: height))) else {
            throw SynthVideoScriptError.graphicConversionError(lineNumber: 0)
        }

        // Get a reference to the bitmap memory layout of the image
        guard let bitmap = cgImage.dataProvider?.data else {
            throw SynthVideoScriptError.graphicConversionError(lineNumber: 0)
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
            throw SynthVideoScriptError.graphicConversionError(lineNumber: 0)
        }
    }
    
    /// For a given tile bitmap and x and y offsets in imagespace, return a dictionary of tiles and their respective positions
    /// in memoryspace.
    internal static func tilesForFrame(in image: [[Tile]], x: Int, y: Int) -> TilePositions {
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
                tiles.add(key: tile, position: try! TileMapPosition(row: UInt8(row % 50), col: UInt8(col % 100)))
            }
        }

        return tiles
    }
    
    // MARK: Synthvideo
    /// Export the video in .synthvid format to the provided URL.
    /// The .synthvid file name extension IS NOT added to the URL.
    /// - Parameter url: The URL to write the file to
    /// - Parameter withoutOverwriting: If false, an existing file at the location will be overwritten. The default is false.
    /// - Throws: `SynthVideoError.outputFileUnavailable` when, for any reason, the file write failed. This includes when a file is not overwritten because of the `withoutOverwriting` parameter was set.
    public func exportSynthvid(url: URL, withoutOverwriting: Bool = false) throws {
        do {
            try synthvid.write(to: url, options: withoutOverwriting ? [.withoutOverwriting] : [])
        } catch {
            throw SynthVideoError.outputFileUnavailable
        }
    }
    
    /// Data of the video in .synthvid compressed format.
    public lazy var synthvid: Data = {
        // Return the value in memory, if available
        if let cached = _synthVid {
            return cached
        }
        
        // Calculate the changes for each frame from the one that preceded it.
        // Assume the first frame is preceded by a blank screen.
        var screenUpdates = [ScreenUpdate?]()
        
        // Track the updates made to the tile map and tile library
        var tileMap = TileMap()
        var tileLibrary = TileLibrary()
        
        // Analyze the entire video, to find when each unique tile appears.
        var tileAppearances = self.tileAppearances
        
        // Track which tiles have made their final appearance, so that
        // they can be safely removed from the tile library
        var releasedTiles = Set<Tile>()
        
        for frameNumber in 0 ..< frames.count {
                        
            let previousScreen = (frameNumber == 0) ? Screen.blank : frames[frameNumber-1]
            let currentScreen = frames[frameNumber]
                        
            // Store the pending writes in dictionaries, to prevent duplicates
            // and ensure that only the last written value is used.
            var tileMapWrites = [TileMapPosition : UInt8]()
            var tileLibraryWrites = [UInt8 : Tile]()
            
            // Create a list of tiles that are released after this screen
            var upcomingReleases = [Tile]()
            
            // Consider each tile that will appear on screen, and their positions
            for (tile, positions) in currentScreen.tilePositions {
                // Sort the positions that will display this tile
                // by what tile library index they currently have.
                
                let positionsByOldIndex = {
                    var positionsByOldIndex = IndexPositions()
                    for position in positions {
                        let oldIndex = tileMap[position]
                        positionsByOldIndex.add(key: oldIndex, position: position)
                    }
                    return positionsByOldIndex
                }()
                
                // Iterate through the tiles, sorted by what value their
                // positions currently hold in the tile map
                for (oldIndex, insidePositions) in positionsByOldIndex {
                    let oldTile = tileLibrary[oldIndex]
                    
                    // If the tile index already points to the needed tile,
                    // continue.
                    if oldTile == tile {
                        continue
                    }
                    
                    // Find the mapping of existing tile map values visible on screen, sorted
                    // by index
                    let tileMapIndexPositions = tileMap.indexPositionsOnScreen(xOffset: currentScreen.xOffset, yOffset: currentScreen.yOffset)
                    
                    // It is more efficient to change the tile library entry for this index than
                    // to change the values in the tile map if:
                    // The number of positions in the drawing area using this tile index is greater than
                    // the number of positions on screen, outside of the drawing area, using the same
                    // tile pattern in both this screen and the previous.
                    let outsidePositions: Set<TileMapPosition> = {
                        tileMapIndexPositions[oldIndex]?.subtracting(insidePositions)
                            .filter({
                                // Filter to keep only positions that show
                                // this tile in both the previous and current
                                // frame.
                                currentScreen.tilePositions[oldTile]?.contains($0) ?? false
                            }) ?? Set<TileMapPosition>()
                    }()
                    
                    // See if it requires fewer moves to update the tile map
                    // or the tile library.
                    // TODO: Update to be based on total CPU cycles or file size
                    let updateLibrary = insidePositions.count > outsidePositions.count
                    
                    if (updateLibrary) {
                        // See how many writes are needed for writing without swapping
                        // a value in the tile library
                        var (standardTileMapWrites, standardTileLibraryWrites, standardReleasedTile) = writesToDraw(tile: tile, drawPositions: insidePositions, library: tileLibrary, tileMap: tileMap, screen: currentScreen, released: releasedTiles)
                        
                        // TODO: FIX ABOVE.
                        // Returns tile map writes that are for the data already in the map
                        // Returns a released value
                        
                        // If the standard approach found the same move as the swap by the space's
                        // availability as a releasable tile, it will have returned unneeded tile map
                        // writes which can be filtered out
                        standardTileMapWrites = standardTileMapWrites.filter { (position, index) in
                            return tileMap[position] != index
                        }
                        
                        // Create a copy of the library, changing the library value
                        // for this index to see how many writes would be needed
                        // to update the screen.
                        var swapLibrary = tileLibrary
                        swapLibrary[oldIndex] = tile
                        
                        // If the swap removed the last instance of a tile that is in the release pool,
                        // make the calculation with that tile removed from the pool
                        let swapReleased = swapLibrary.indicesForTile[oldTile] == nil ? releasedTiles.subtracting([oldTile]) : releasedTiles
                        
                        let (swapTileMapWrites, swapTileLibraryWrites, swapReleasedTile) = writesToDraw(tile: oldTile, drawPositions: outsidePositions, library: swapLibrary, tileMap: tileMap, screen: currentScreen, released: swapReleased)

                        // Find the number of writes needed for the two algorithms
                        let standardWrites = standardTileMapWrites.count + standardTileLibraryWrites.count
                        let swapWrites = swapTileMapWrites.count + swapTileLibraryWrites.count + 1
                        
                        // Do the final update based on which path requires fewer writes
                        if swapWrites < standardWrites {
                            // Swap
                            // See if the old tile removed in the swap needs to be removed from the library
                            //let swappedTile = tileLibrary[oldIndex]
                            tileLibrary[oldIndex] = tile
                            tileLibraryWrites[oldIndex] = tile
                            // See if the tile that was removed was in the release pool,
                            // and if it was the last instance of that tile, remove the
                            // tile from the pool.
                            if releasedTiles.contains(oldTile) {
                                if tileLibrary.indicesForTile[oldTile] == nil {
                                    releasedTiles.remove(oldTile)
                                }
                            }
                            
                            tileMapWrites.merge(swapTileMapWrites, uniquingKeysWith: replaceMerge)
                            tileLibraryWrites.merge(swapTileLibraryWrites, uniquingKeysWith: replaceMerge)
                            applyUpdates(mapWrites: swapTileMapWrites, libraryWrites: swapTileLibraryWrites, releasedTile: swapReleasedTile, tileMap: &tileMap, tileLibrary: &tileLibrary, released: &releasedTiles)
                        } else {
                            tileMapWrites.merge(standardTileMapWrites, uniquingKeysWith: replaceMerge)
                            tileLibraryWrites.merge(standardTileLibraryWrites, uniquingKeysWith: replaceMerge)
                            applyUpdates(mapWrites: standardTileMapWrites, libraryWrites: standardTileLibraryWrites, releasedTile: standardReleasedTile, tileMap: &tileMap, tileLibrary: &tileLibrary, released: &releasedTiles)
                        }
                                                

                    } else {
                        // Add the update events to the array
                        let (newTileMapWrites, newTileLibraryWrites, newReleasedTile) = writesToDraw(tile: tile, drawPositions: insidePositions, library: tileLibrary, tileMap: tileMap, screen: currentScreen, released: releasedTiles)
                        tileMapWrites.merge(newTileMapWrites, uniquingKeysWith: replaceMerge)
                        tileLibraryWrites.merge(newTileLibraryWrites, uniquingKeysWith: replaceMerge)
                        applyUpdates(mapWrites: newTileMapWrites, libraryWrites: newTileLibraryWrites, releasedTile: newReleasedTile, tileMap: &tileMap, tileLibrary: &tileLibrary, released: &releasedTiles)
                    }
                }
                
                if tileAppearances[tile]!.last! == frameNumber {
                    upcomingReleases.append(tile)
                    // Remove the tile from tileAppearances so there are
                    // fewer to search through in the future
                    tileAppearances.removeValue(forKey: tile)
                } else {
                    tileAppearances[tile]!.remove(at: 0)
                }
                
                // Write any changes to the tile map and tile library for the
                // next iteration.
                for write in tileMapWrites {
                    tileMap[write.key] = write.value
                }
                for write in tileLibraryWrites {
                    tileLibrary[write.key] = write.value
                }
            }
            
            // Update the releasedTiles set with tiles last used in this frame
            for release in upcomingReleases {
                releasedTiles.insert(release)
            }
            
            // If there are no updates, insert nil into the updates array.
            // Otherwise, format the screen update and insert it to the array.
            if (currentScreen.xOffset == previousScreen.xOffset &&
                currentScreen.yOffset == previousScreen.yOffset &&
                tileMapWrites.isEmpty && tileLibraryWrites.isEmpty) {
                screenUpdates.append(nil)
            } else {
                let screenUpdate = ScreenUpdate(xOffset: currentScreen.xOffset, yOffset: currentScreen.yOffset, tileMapWrites: tileMapWrites, tileLibraryWrites: tileLibraryWrites)
                screenUpdates.append(screenUpdate)
            }
        }
                
        // Write the updates into the dat file format.
        var outputData = Data()
        
        var delayCount: UInt16 = 0
        
        for update in screenUpdates {
            if let update {
                // Write any pending delays
                if delayCount > 0 {
                    outputData.appendUInt16(0xBABE)
                    outputData.appendUInt16(delayCount)
                }
                delayCount = 0
                // Write the x and y offsets
                outputData.appendUInt16(update.xOffset)
                outputData.appendUInt16(update.yOffset)
                
                // Write the respective update counts
                outputData.appendUInt16(UInt16(update.tileLibraryWrites.count))
                outputData.appendUInt16(UInt16(update.tileMapWrites.count))
                
                // Write the library updates. Each update takes 16 bytes of space
                let orderedLibraryUpdates = update.tileLibraryWrites.sorted { first, second in
                    return first.key < second.key
                }
                for libUpdate in orderedLibraryUpdates {
                    // The UInt8 index number is written as a UInt32 value
                    // in little endian format to preserve alignment
                    outputData.append(contentsOf: [libUpdate.key, 0, 0, 0])
                    outputData.append(contentsOf: libUpdate.value.pixels)
                }
                
                // Write the tilemap updates.
                let orderedTileMapUpdates = update.tileMapWrites.sorted { first, second in
                    return first.key < second.key
                }
                for tileMapUpdate in orderedTileMapUpdates {
                    // Write the coordinates for the tile, followed by the library index and 0
                    outputData.append(contentsOf: [tileMapUpdate.key.row, tileMapUpdate.key.col, tileMapUpdate.value, 0])
                }
            } else {
                delayCount += 1
            }
        }
        // Write any delays from the end of the video
        if delayCount > 0 {
            outputData.appendUInt16(0xBABE)
            outputData.appendUInt16(delayCount)
        }
        
        // Finish off the file with 0xBEEF 0xCAFE
        outputData.appendUInt16(0xBEEF)
        outputData.appendUInt16(0xCAFE)
        
        // Save the encoded data to the cache
        _synthVid = outputData
        
        // Write the data to file
        return outputData
    }()
    
    /// Re-encode the synthvid data.
    /// This would be useful for loading a synthvid file from disk and processing the video
    /// with an updated encoder.
    public func encodeSynthvid() {
        // Delete the cached version in memory
        _synthVid = nil
        // Process the encoding, which saves to the cache automatically.
        _ = synthvid
        
    }

    /// Return a dictionary that maps each tile that appears in the video to its appearances.
    /// This allows the optimization stage of exporting to .dat to free references to a tile once
    /// it is no longer needed.
    private var tileAppearances: [Tile : [Int]] {
        var appearances = [Tile : [Int]]()
        
        for (frameNumber, frame) in frames.enumerated() {
            for tile in frame.tilePositions.keys {
                // If this tile has been seen before, append this frame number.
                // If it has been seen before, append this appearance.
                if appearances[tile] != nil {
                    appearances[tile]!.append(frameNumber)
                } else {
                    appearances[tile] = [frameNumber]
                }
            }
        }
        
        return appearances
    }
    
}

// MARK: Synthvideo helper functions

typealias TileMapWrites = [TileMapPosition : UInt8]
typealias TileLibraryWrites = [UInt8 : Tile]

fileprivate struct ScreenUpdate {
    let xOffset: UInt16
    let yOffset: UInt16
    let tileMapWrites: TileMapWrites
    let tileLibraryWrites: TileLibraryWrites
}


/// Find which write operations are required to make write the given tile at the given positions into a library and tilemap, in the context of a screen, knowing that a set of tiles
/// are no longer needed.
fileprivate func writesToDraw(tile: Tile, drawPositions: Set<TileMapPosition>, library: TileLibrary, tileMap: TileMap, screen: Screen, released: Set<Tile>) -> (tileMapWrites: TileMapWrites, tileLibraryWrites : TileLibraryWrites, releasedTile: Tile?) {
    
    var tileMapWrites = TileMapWrites()
    var tileLibraryWrites = TileLibraryWrites()
    
    // If the tile is already in the library, simply do the writes
    // using the library index that already has the most appearances
    // in the tile map
    if let matchingIndices = library.indicesForTile[tile] {
        // Sort the matches by:
        // 1: Number of positions using the index on screen
        // 2: Number of positions using the index total
        // 3: Index number
        let writeIndex: UInt8 = {
            // Map the indices to tuples containing the
            // sort parameters, sort, and return the first one
            matchingIndices.map { index in
                let allPositions = tileMap.positionsByIndex[Int(index)]
                let onscreenPositions = allPositions.intersection(screen.screenPositions)

                return (onScreen: onscreenPositions.count, inMap: allPositions.count, index: index)
            }.sorted { first, second in
                // Prefer the fewest positions on-screen
                if (first.onScreen < second.onScreen) {
                    return true
                } else if (first.onScreen > second.onScreen) {
                    return false
                }
                // Next prefer the fewest positions overall
                if (first.inMap < second.inMap) {
                    return true
                } else if (first.inMap > second.inMap) {
                    return false
                }
                // Finally, prefer the lowest index
                if (first.index < second.index) {
                    return true
                } else {
                    return false
                }
            }.first!.index
            
        }()

        for drawPosition in drawPositions {
            tileMapWrites[drawPosition] = writeIndex
        }
        return (tileMapWrites, tileLibraryWrites, nil)
    }
    
    // If the tile is not in the library, see if there is a released tile space that can be used
    if released.count > 0 {
        // Use the first index that appears in the release pool
        let (writeIndex, releasedTile) = {
            let (writeIndexInt, releasedTile) = library.tileForIndex.enumerated().first { (_, potentialRelease) in
                released.contains(potentialRelease)
            }!
            
            return (UInt8(writeIndexInt), releasedTile)
        }()

        // Update the tile library
        tileLibraryWrites[writeIndex] = tile
                
        for drawPosition in drawPositions {
            tileMapWrites[drawPosition] = writeIndex
        }
        return (tileMapWrites, tileLibraryWrites, releasedTile)
    }
    
    // See if there is a tile pattern occupying multiple positions in the tile library,
    // consolodate the tiles into one library index, and adjust the tile map as needed.
    if library.hasDuplicates {
        // Filter the library down to the tiles with duplicate indices
        let duplicates = library.indicesForTile.filter { indices in
            indices.value.count > 1
        }
        // This should only occur if bad data was passed in; no valid screen should contain more
        // than 256 unique tiles
        if duplicates.isEmpty {
            fatalError()
        }
        
        // Sort all duplicate indices by:
        // 1: Fewest appearances on screen
        // 2: Fewest appearances in the map
        // 3: Lowest index
        let writeIndex: UInt8 = {
            // Reduce to a set of all indices of duplicates.
            // e.g., if a tile were at indices 0 and 1, both will appear
            // in the resulting set
            let allIndices = duplicates.values.reduce([UInt8]()) { partialResult, indices in
                return partialResult + Array(indices)
            }
            // Map the indices to tuples of the sorting criteria, then
            // sort to find the best choice and return it
            let sorted = allIndices.map { index in
                let allPositions = tileMap.positionsByIndex[Int(index)]
                let onScreenPositions = allPositions.intersection(screen.screenPositions)
                return (onScreen: onScreenPositions.count, inMap: allPositions.count, index: index)
            }
            .sorted { first, second in
                // Prefer fewer positions on screen
                if first.onScreen < second.onScreen {
                    return true
                } else if first.onScreen > second.onScreen {
                    return false
                }
                // Prefer fewer positions in the tilemap overall
                if first.inMap < second.inMap {
                    return true
                } else if first.inMap > second.inMap {
                    return false
                }
                
                // Prefer the lower index
                if first.index < second.index {
                    return true
                } else {
                    return false
                }
            }
            
            return sorted.first!.index
        }()
        // Find the index of this tile with the most
        // usage in the current tile map (excluding
        // the write index)
        let mergeTile = library.tileForIndex[Int(writeIndex)]
        let mergeIndex: UInt8 = {
            // Find all indices for the selected tile except for writeIndex.
            
            let tileIndices = library.indicesForTile[mergeTile]!.subtracting([writeIndex])
            // Map the indices into tuples for sorting
            let sorted = tileIndices.map { index in
                // Find the number of appearances for each index
                let appearanceCount = tileMap.positions(for: index).count
                return (appearances: appearanceCount, index: index )
            }
            .sorted { first, second in
                // Prefer the highest count
                if first.appearances > second.appearances {
                    return true
                } else if first.appearances < second.appearances {
                    return false
                }
                // Prefer the lower index
                if first.index < second.index {
                    return true
                } else {
                    return false
                }
            }
            return sorted.first!.index
        }()
        
        // Change every on-screen position using writeIndex that
        // will continue to show the same tile in the current frame
        // to use mergeIndex
        // TODO: Update to consider only tiles that need to be maintained
        // Find the positions that use the merge index on-screen, then filter them
        // to the positions that will continue to show this tile
        let changePositions = tileMap.positions(for: writeIndex)
            .intersection(screen.screenPositions)
            .intersection(screen.tilePositions[mergeTile] ?? Set<TileMapPosition>())
        
        for position in changePositions {
            tileMapWrites[position] = mergeIndex
        }
        
        // Update writeIndex to use the new tile
        tileLibraryWrites[writeIndex] = tile
        
        // Update the draw positions to use writeIndex
        for position in drawPositions {
            tileMapWrites[position] = writeIndex
        }
        
        return (tileMapWrites, tileLibraryWrites, nil)
    }
    
    // Finally, address the situation where a tile must be freed now, though it
    // will appear again later.
    
    // Create a set of tiles that are in the tile library, but not in the current screen
    let tilesInLibrary = Set<Tile>(library.tileForIndex)
    let removeableTiles = tilesInLibrary.subtracting(screen.tiles)
    
    // TODO: Find an optimal tile to use
    guard removeableTiles.count > 0 else {
        fatalError()
    }
    let removedTile = removeableTiles.first!
    let writeIndex = library.indicesForTile[removedTile]!.first!
    
    // Load the tile
    tileLibraryWrites[writeIndex] = tile
    
    // Update the tile map
    for drawPosition in drawPositions {
        tileMapWrites[drawPosition] = writeIndex
    }
    return (tileMapWrites, tileLibraryWrites, nil)
}

/// Apply the sets of writes returned from writesToDraw(::::::) into the given tilemap, library, and set of released tiles.
fileprivate func applyUpdates(mapWrites: TileMapWrites, libraryWrites: TileLibraryWrites, releasedTile: Tile?, tileMap: inout TileMap, tileLibrary: inout TileLibrary, released: inout Set<Tile>) {
    for mapWrite in mapWrites {
        tileMap[mapWrite.key] = mapWrite.value
    }
    for libraryWrite in libraryWrites {
        tileLibrary[libraryWrite.key] = libraryWrite.value
    }
    if let releasedTile {
        // If the tile that was released is no longer in
        // the tile library, remove it from the release pool.
        if tileLibrary.indicesForTile[releasedTile] == nil {
            released.remove(releasedTile)
        }
        
    }
}

/// Convenience method used as an argument to the .merge method of Dictionary, so that duplicate entries are replaced.
fileprivate func replaceMerge<T> (oldValue: T, newValue: T) -> T {
    newValue
}

/// Convenience method to append a 16-bit value into a Data struct in little-endian order.
fileprivate extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        // Append the bytes in little endian order
        let bytes = [UInt8(value & 0xFF), UInt8(value >> 8)]
        self.append(contentsOf: bytes)
    }
}

