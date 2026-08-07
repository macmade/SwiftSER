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

    /// The thirteen fields of a SER header, as a value a test can vary.
    ///
    /// Tests start from ``wellFormedHeader`` and change only the fields their
    /// subject depends on, so each test shows its own deviation and nothing
    /// else. Fields needing a byte pattern no typed property can express are set
    /// by mutating ``data`` at the matching ``HeaderOffset``.
    struct Header
    {
        /// The 14-byte file ID.
        var fileID: String

        /// The Lumenera camera series ID.
        var luID: Int32

        /// The raw color ID.
        var colorID: Int32

        /// The 16-bit image data byte-order flag.
        var littleEndian: Int32

        /// The image width, in pixels.
        var imageWidth: Int32

        /// The image height, in pixels.
        var imageHeight: Int32

        /// The true bit depth per pixel per plane.
        var pixelDepthPerPlane: Int32

        /// The number of image frames the header declares.
        var frameCount: Int32

        /// The observer name.
        var observer: String

        /// The instrument name.
        var instrument: String

        /// The telescope name.
        var telescope: String

        /// The local start time, in 100 ns ticks.
        var dateTime: Int64

        /// The UTC start time, in 100 ns ticks.
        var dateTimeUTC: Int64

        /// The number of bytes one frame of this geometry occupies.
        ///
        /// Derived from the specification's own tables rather than from
        /// ``SERHeader``, so a mistake in the library cannot hide behind the
        /// same mistake in the fixtures. Geometry that would overflow or run
        /// negative yields zero, since a fixture builder must not trap.
        var bytesPerFrame: Int
        {
            let planes        = ( self.colorID == 100 || self.colorID == 101 ) ? 3 : 1
            let bytesPerPixel = ( self.pixelDepthPerPlane <= 8 ? 1 : 2 ) * planes

            let ( pixels, pixelOverflow ) = Int( self.imageWidth ).multipliedReportingOverflow( by: Int( self.imageHeight ) )
            let ( bytes,  byteOverflow  ) = pixels.multipliedReportingOverflow( by: bytesPerPixel )

            guard pixelOverflow == false, byteOverflow == false
            else
            {
                return 0
            }

            return max( 0, bytes )
        }

        /// The 178 bytes the fields encode to.
        var data: Data
        {
            let fields: [ [ UInt8 ] ] = [
                TestUtilities.asciiField( self.fileID, width: 14 ),
                TestUtilities.littleEndianBytes( self.luID ),
                TestUtilities.littleEndianBytes( self.colorID ),
                TestUtilities.littleEndianBytes( self.littleEndian ),
                TestUtilities.littleEndianBytes( self.imageWidth ),
                TestUtilities.littleEndianBytes( self.imageHeight ),
                TestUtilities.littleEndianBytes( self.pixelDepthPerPlane ),
                TestUtilities.littleEndianBytes( self.frameCount ),
                TestUtilities.asciiField( self.observer,   width: 40 ),
                TestUtilities.asciiField( self.instrument, width: 40 ),
                TestUtilities.asciiField( self.telescope,  width: 40 ),
                TestUtilities.littleEndianBytes( self.dateTime ),
                TestUtilities.littleEndianBytes( self.dateTimeUTC ),
            ]

            return Data( fields.flatMap { $0 } )
        }

        /// As many frames of this geometry as the header declares, each filled
        /// with its own index.
        var indexedFrames: [ [ UInt8 ] ]
        {
            TestUtilities.indexedFrames( count: Int( self.frameCount ), bytesPerFrame: self.bytesPerFrame )
        }

        /// A file holding exactly the frames this header declares, and no
        /// trailer.
        ///
        /// The agreeing case. A file whose header disagrees with its contents —
        /// the subject of the reconciliation tests — is built through ``File``'s
        /// own initializer, so the disagreement is spelled out where it is made.
        var file: File
        {
            File( header: self, frames: self.indexedFrames, timestamps: nil )
        }

        /// A copy of the header with one or more fields changed.
        ///
        /// For the call sites where naming a local would break up a batch of
        /// assertions meant to be read side by side.
        ///
        /// - Parameter change: What to change on the copy.
        /// - Returns: The changed copy.
        func changing( _ change: ( inout Header ) -> Void ) -> Header
        {
            var copy = self

            change( &copy )

            return copy
        }
    }

    /// A synthetic SER file: a header, the frames it holds, and its trailer.
    ///
    /// ``Header/frameCount`` and ``frames`` are deliberately independent, so a
    /// file can be made to disagree with what its header declares.
    struct File
    {
        /// The header the file opens with.
        var header: Header

        /// Each frame's bytes, in frame order.
        var frames: [ [ UInt8 ] ]

        /// The trailer's tick values, or `nil` for no trailer at all.
        var timestamps: [ Int64 ]?

        /// The file's bytes.
        var data: Data
        {
            let trailer = ( self.timestamps ?? [] ).flatMap
            {
                TestUtilities.littleEndianBytes( $0 )
            }

            return self.header.data + Data( self.frames.flatMap { $0 } ) + Data( trailer )
        }
    }

    /// A header whose every field is valid: MONO, 4×2 pixels, 8-bit, one frame,
    /// no start date and so no timestamp trailer.
    ///
    /// The one place a fixture's baseline is written down. A test that depends
    /// on any of these values states it rather than inheriting it silently.
    static var wellFormedHeader: Header
    {
        Header(
            fileID:             "LUCAM-RECORDER",
            luID:               0,
            colorID:            0,
            littleEndian:       1,
            imageWidth:         4,
            imageHeight:        2,
            pixelDepthPerPlane: 8,
            frameCount:         1,
            observer:           "Observer",
            instrument:         "Instrument",
            telescope:          "Telescope",
            dateTime:           0,
            dateTimeUTC:        0
        )
    }

    /// A header whose every field is valid, declaring a given number of frames.
    ///
    /// - Parameter frameCount: The number of frames the header declares.
    /// - Returns: ``wellFormedHeader`` with its frame count changed.
    static func wellFormedHeader( frameCount: Int32 ) -> Header
    {
        Self.wellFormedHeader.changing { $0.frameCount = frameCount }
    }

    /// Builds frames filled with their own index.
    ///
    /// A decoded frame can then be told apart from its neighbours.
    ///
    /// - Parameters:
    ///   - count:         The number of frames to build.
    ///   - bytesPerFrame: The size of each frame, in bytes.
    /// - Returns: The frames, in frame order.
    static func indexedFrames( count: Int, bytesPerFrame: Int ) -> [ [ UInt8 ] ]
    {
        ( 0 ..< max( 0, count ) ).map
        {
            [ UInt8 ]( repeating: UInt8( truncatingIfNeeded: $0 ), count: max( 0, bytesPerFrame ) )
        }
    }

    /// Writes data to a uniquely named file in the temporary directory.
    ///
    /// - Parameters:
    ///   - data: The bytes to write.
    ///   - name: The file name to use.
    /// - Returns: The URL the data was written to.
    /// - Throws: Any error raised while writing.
    static func temporaryFile( containing data: Data, named name: String ) throws -> URL
    {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent( UUID().uuidString )

        try FileManager.default.createDirectory( at: directory, withIntermediateDirectories: true )

        let url = directory.appendingPathComponent( name )

        try data.write( to: url )

        return url
    }
}
