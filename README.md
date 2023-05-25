# SynthVideo

This package provides a method for viewing, exporting, and creating
one-bit video data in the proprietary format used by my STM32 based
computer system and synthesizer. This package is primarily used in
my own Macintosh application that generates videos for it, but is
provided as a BSD-licensed open source package for any interested
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
- Yet undreamed of ways to be harder, better, faster, and/or stronger.
