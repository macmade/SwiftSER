/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2026, Jean-David Gadina - www.xs-labs.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the Software), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 ******************************************************************************/

import Foundation
@testable import SwiftSER
import Testing

/// Shared fixtures and synthetic-file builders for the test suite.
class TestUtilities
{
    /// The byte offset of each header field, as implied by the field order and
    /// lengths the specification gives.
    enum HeaderOffset
    {
        /// The offset of the 14-byte file ID.
        static let fileID = 0

        /// The offset of the Lumenera camera series ID.
        static let luID = 14

        /// The offset of the color ID.
        static let colorID = 18

        /// The offset of the 16-bit image data byte-order flag.
        static let littleEndian = 22

        /// The offset of the image width.
        static let imageWidth = 26

        /// The offset of the image height.
        static let imageHeight = 30

        /// The offset of the pixel depth per plane.
        static let pixelDepthPerPlane = 34

        /// The offset of the frame count.
        static let frameCount = 38

        /// The offset of the 40-byte observer name.
        static let observer = 42

        /// The offset of the 40-byte instrument name.
        static let instrument = 82

        /// The offset of the 40-byte telescope name.
        static let telescope = 122

        /// The offset of the local start time.
        static let dateTime = 162

        /// The offset of the UTC start time.
        static let dateTimeUTC = 170
    }

    /// Encodes an integer as little-endian bytes.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: The value's bytes, least significant first.
    static func littleEndianBytes< T: FixedWidthInteger >( _ value: T ) -> [ UInt8 ]
    {
        ( 0 ..< MemoryLayout< T >.size ).map
        {
            UInt8( truncatingIfNeeded: value >> ( $0 * 8 ) )
        }
    }

    /// Encodes a string as a fixed-width field, padded with NUL bytes.
    ///
    /// - Parameters:
    ///   - string: The text to encode. Truncated if it exceeds `width` bytes.
    ///   - width:  The field's fixed width, in bytes.
    /// - Returns: Exactly `width` bytes.
    static func asciiField( _ string: String, width: Int ) -> [ UInt8 ]
    {
        let bytes = Array( string.utf8.prefix( width ) )

        return bytes + Array( repeating: 0, count: width - bytes.count )
    }

    /// Builds a synthetic 178-byte SER header.
    ///
    /// Every parameter defaults to a valid value, so a test names only the
    /// fields it cares about. Fields that need a byte pattern no typed
    /// parameter can express are set by mutating the returned data at the
    /// matching ``HeaderOffset``.
    ///
    /// - Parameters:
    ///   - fileID:             The 14-byte file ID.
    ///   - luID:               The Lumenera camera series ID.
    ///   - colorID:            The raw color ID.
    ///   - littleEndian:       The 16-bit image data byte-order flag.
    ///   - imageWidth:         The image width, in pixels.
    ///   - imageHeight:        The image height, in pixels.
    ///   - pixelDepthPerPlane: The true bit depth per pixel per plane.
    ///   - frameCount:         The number of image frames.
    ///   - observer:           The observer name.
    ///   - instrument:         The instrument name.
    ///   - telescope:          The telescope name.
    ///   - dateTime:           The local start time, in 100 ns ticks.
    ///   - dateTimeUTC:        The UTC start time, in 100 ns ticks.
    /// - Returns: The 178 header bytes.
    static func headerData(
        fileID:             String = "LUCAM-RECORDER",
        luID:               Int32  = 0,
        colorID:            Int32  = 0,
        littleEndian:       Int32  = 1,
        imageWidth:         Int32  = 4,
        imageHeight:        Int32  = 2,
        pixelDepthPerPlane: Int32  = 8,
        frameCount:         Int32  = 1,
        observer:           String = "Observer",
        instrument:         String = "Instrument",
        telescope:          String = "Telescope",
        dateTime:           Int64  = 0,
        dateTimeUTC:        Int64  = 0
    )
    -> Data
    {
        let fields: [ [ UInt8 ] ] = [
            Self.asciiField( fileID, width: 14 ),
            Self.littleEndianBytes( luID ),
            Self.littleEndianBytes( colorID ),
            Self.littleEndianBytes( littleEndian ),
            Self.littleEndianBytes( imageWidth ),
            Self.littleEndianBytes( imageHeight ),
            Self.littleEndianBytes( pixelDepthPerPlane ),
            Self.littleEndianBytes( frameCount ),
            Self.asciiField( observer,   width: 40 ),
            Self.asciiField( instrument, width: 40 ),
            Self.asciiField( telescope,  width: 40 ),
            Self.littleEndianBytes( dateTime ),
            Self.littleEndianBytes( dateTimeUTC ),
        ]

        return Data( fields.flatMap { $0 } )
    }
}
