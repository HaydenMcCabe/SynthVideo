# SynthVideo

This package provides a method for viewing, exporting, and creating
one-bit video data in the proprietary format used by my STM32 based
computer system and synthesizer, and other popular video formats including H.264. 
This package is primarily used in my own Macintosh application that generates videos 
for it, but is provided as a BSD-licensed open source package for any interested
parties to browse, adapt, or learn from. Please see the `LICENSE` file
for the full text of the license agreement.

## Requirements

This package has fairly high system requirements, as I am likely to always
be its primary - if not only - user, and the computer on which it is being developed
is capable of meeting them. 

The requirements for the current version of the package are:
- Swift toolchain version 5.8 or later
- macOS version 13 (Ventura) or iOS/iPadOS version 16

Although Linux compatibility may be possible with some API
breaking changes to functions that use Apple Core Graphics types, it is not being planned for.

## Video Hardware Details

The display for which these videos are designed is based on a
one-bit, tile-based, graphics system. Up to 256 unique 8x12 pixel tiles
can be displayed on screen at one time. They are arranged in a tilemap
of 100x50 tiles. This allows for an 800x600 pixel image to be held in memory,
with a 400x300 pixel area of it to be displayed on-screen.

The area to be displayed is determined by the x-offset and y-offset values,
which gives a value in the range 0...799 for x and 0...599 for y, giving a
coordinate (x-offset, y-offset) of the pixel in the 800x600 pixel image
in memory to be used as the upper left corner of the image on-screen. 
The on-screen image will wrap pixels around either axis, so an image with an offset
of (600, 450) will display pixels from the 800x600 in-memory image in the range 
600...799,0...199 for x, and 450...599,0...149 for y.

This allows for a display that is capable of smooth scrolling along any line
or curve, and provides a large amount of off-screen space to allow drawing
commands to be optimized for smooth operation.

The currently runs at a static 30 frames per second (FPS), although the video
hardware is capable of 60 FPS. 30 FPS video was chosen as a compromise between
smooth video and efficient use of the limited  space available on the
embedded system's storage.

## .synthvid Format

To be usable as video data on the hardware, the video is compressed into an optimized
format with the preferred extension .synthvid. The format is designed so that the hardware can
update the video memory as quickly as possible. To that end, the video is arranged as a series of
commands, followed by their respective data. The decoder can process a command and then keep a pointer
to the address of the next byte, which can be processed when the next frame is to be displayed.

There are 3 commands that are used in the current version of .synthvid. The `reset` and `pause` commands
are identified by a magic number, followed by its argument. The third command, to write updates into
video memory, is processed when neither of the other commands is recognized.

All commands are sized so that they conform to 32-bit alignment.

### `Reset`

The reset command will clear the video memory and return to the first frame of the video.
It is identified by the following little-endian, 16-bit, unsigned integers:

```
0xBEEF
0xCAFE
```

### `Pause`

The pause command takes an argument `n`, as a 16-bit unsigned integer, designating that there are no changes
to be made for `n` frames.
It has the following format, with the magic number and argument `N` both read as little-endian, 16-bit, unsigned integers.

```
0xBABE
N (UInt16)
```

### `Update`

If reading the 16-bit value in a command can not be interpreted as `reset` or `pause`, it is interpreted as
an update command. The frame starts with 4 UInt16 values: the x-offset and y-offset values to be used, followed
by the number of updates to be made to the tile library (`L`) and tile map (`M`). This is followed by `L` values that
describe the new data to be written into a tile library location, and the index to write to. Finally, there are `M`
values describing the updates to be made to the tile map, with the row and column to be updated, and the new index
value to be written.

```
x-offset (UInt16)
y-update (UInt16)
L (UInt16)
M (UInt 16)

// Tile Library Updates (repeats L times)
Library index (UInt32)
Tile rows 0-3 (UInt32)
Tile rows 4-7 (UInt32)
Tile rows 8-11 (UInt32)

// Tile Map Updates (repeats M times)
Tile map row (UInt8)
Tile map column (UInt8)
New tile map index (UInt16)
```

## Usage

**Note: This software, in its 0.x versions, is considered to be a beta release and does not guarantee a stable API**
*A version 1.0 release will follow standard semantic versioning standards re: API stability*

Add a link to auto-generated documentation here

Add a link to a guide to the SynthVideo scripting language here

## Future Development

Future development will largely be driven by projects I am, or will be, planning for the use of
the STM32 based computer system on which the videos are used. Some potential revisions include:

- A command to vary the frame rate, allowing for 60, 30, and potentially lower frame rates.
- A way of synchronizing OPL3 synthesizer commands to the video, allowing the hardware to play
videos with FM sound.
- A color option to allow a 24-bit color to be assigned on a per-frame basis, once the necessary
hardware has been built.
- Optimizations that arrange the write operations in .synthvid data to reduce the maximum number of
write operations per frame, thus reducing the time the video hardware spends handling high priority
interrupts. 
- Yet undreamed of ways to be harder, better, faster, and/or stronger.
