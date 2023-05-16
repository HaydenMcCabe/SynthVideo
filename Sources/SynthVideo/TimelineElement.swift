//
//  TimelineElement.swift
//  STM32VideoToolkit
//
//  Created by Hayden McCabe on 4/15/23.
//

import Foundation

/// The uncompressed video format consists of two types of element:
/// - screen: A screen to display onscreen, including the tiles needed, their
/// positions, and the x and y offsets.
/// - delay: A delay of n frames, while the screen will be unchanged.
public enum TimelineElement {
    ///  - An image to be drawn to screen, with the tiles used, their positions in the tilemap,
    ///    and the offset in the tilemap
    case screen(screen: Screen, range: ClosedRange<Int>)
    ///  - A delay of n frames
    case delay(delay: UInt16, range: ClosedRange<Int>)
    /// All timeline elements store a range of frames for this event.
    /// This computed property allows any timeline element to return its
    /// range directly.
    var range: ClosedRange<Int> {
        switch self {
        case let .delay( _,  range):
            return range
        case let .screen( _,  range):
            return range
        }
    }
}

