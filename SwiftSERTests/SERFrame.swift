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

struct Test_SERFrame
{
    /// A tick value naming a valid instant, so a file can declare a trailer.
    static let startTicks = Int64( 635_000_000_000_000_000 )

    /// The instant ``startTicks`` names.
    static let startDate = Date( timeIntervalSince1970: 1_364_403_200 )

    /// Each depth boundary, with the bytes storing its largest conforming
    /// value and the sample those bytes decode to. The two-byte rows are
    /// little-endian, which is the builder's default.
    static let depthBoundaries: [ ( depth: Int32, bytes: [ UInt8 ], sample: Double ) ] = [
        ( 1,  [ 0x80 ],       128.0 ),
        ( 5,  [ 0xF8 ],       248.0 ),
        ( 8,  [ 0xFF ],       255.0 ),
        ( 9,  [ 0xFF, 0x01 ], 511.0 ),
        ( 12, [ 0xFF, 0x0F ], 4095.0 ),
        ( 16, [ 0xFF, 0xFF ], 65535.0 ),
    ]

    /// A one-frame file for each shape the two widening implementations have to
    /// agree on, its samples stepping so that no two are equal.
    static var decodingPathCases: [ ( name: String, data: Data ) ]
    {
        func shape( name: String, colorID: Int32, imageWidth: Int32, imageHeight: Int32, pixelDepthPerPlane: Int32, littleEndian: Int32, step: Int ) -> ( name: String, data: Data )
        {
            var fields = TestUtilities.wellFormedHeader

            fields.colorID            = colorID
            fields.imageWidth         = imageWidth
            fields.imageHeight        = imageHeight
            fields.pixelDepthPerPlane = pixelDepthPerPlane
            fields.littleEndian       = littleEndian
            fields.frameCount         = 1

            let frame = ( 0 ..< fields.bytesPerFrame ).map { UInt8( truncatingIfNeeded: $0 * step ) }

            return ( name, TestUtilities.File( header: fields, frames: [ frame ], timestamps: nil ).data )
        }

        return [
            shape( name: "8-bit mono",                colorID: 0,   imageWidth: 4, imageHeight: 4, pixelDepthPerPlane: 8,  littleEndian: 1, step: 16 ),
            shape( name: "16-bit mono little-endian", colorID: 0,   imageWidth: 4, imageHeight: 4, pixelDepthPerPlane: 16, littleEndian: 1, step: 8 ),
            shape( name: "16-bit mono big-endian",    colorID: 0,   imageWidth: 4, imageHeight: 4, pixelDepthPerPlane: 16, littleEndian: 0, step: 8 ),
            shape( name: "8-bit BGR",                 colorID: 101, imageWidth: 2, imageHeight: 2, pixelDepthPerPlane: 8,  littleEndian: 1, step: 1 ),
            shape( name: "16-bit BGR little-endian",  colorID: 101, imageWidth: 2, imageHeight: 2, pixelDepthPerPlane: 16, littleEndian: 1, step: 1 ),
            shape( name: "16-bit BGR big-endian",     colorID: 101, imageWidth: 2, imageHeight: 2, pixelDepthPerPlane: 16, littleEndian: 0, step: 1 ),
        ]
    }

    @Test
    func everyDecodingTableIsListed() async throws
    {
        // The tests below iterate these tables, so a row dropped from one would
        // leave them passing while proving less.
        #expect( Self.depthBoundaries.map { $0.depth }   == [ 1, 5, 8, 9, 12, 16 ] )
        #expect( Self.decodingPathCases.map { $0.name }  == [ "8-bit mono", "16-bit mono little-endian", "16-bit mono big-endian", "8-bit BGR", "16-bit BGR little-endian", "16-bit BGR big-endian" ] )
    }

    // MARK: - Raw bytes

    @Test
    func rawDataHoldsTheFrameBytesUntouched() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 2
        fields.frameCount  = 2

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4 ], [ 5, 6, 7, 8 ] ], timestamps: nil ).data
        let file  = try SERFile( data: data, options: .strict )
        let first = try file.frame( at: 0 )
        let last  = try file.frame( at: 1 )

        #expect( Array( first.rawData ) == [ 1, 2, 3, 4 ] )
        #expect( Array( last.rawData )  == [ 5, 6, 7, 8 ] )
        #expect( first.index            == 0 )
        #expect( last.index             == 1 )
    }

    @Test
    func rawDataIsUnaffectedByTheByteOrderFlag() async throws
    {
        // The flag governs decoding, not the bytes the file holds.
        let bytes  = [ [ UInt8 ]( [ 0x12, 0x34, 0x56, 0x78 ] ) ]
        var fields = TestUtilities.wellFormedHeader

        fields.littleEndian       = 1
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = Int32( bytes.count )

        let little = TestUtilities.File( header: fields, frames: bytes, timestamps: nil ).data

        fields.littleEndian = 0

        let big = TestUtilities.File( header: fields, frames: bytes, timestamps: nil ).data

        #expect( try Array( SERFile( data: little, options: .strict ).frame( at: 0 ).rawData ) == [ 0x12, 0x34, 0x56, 0x78 ] )
        #expect( try Array( SERFile( data: big,    options: .strict ).frame( at: 0 ).rawData ) == [ 0x12, 0x34, 0x56, 0x78 ] )
    }

    // MARK: - Sample decoding

    @Test
    func decodesEightBitSamplesInRowMajorOrder() async throws
    {
        // The first stored pixel is the image's upper-left one, and rows follow
        // one another, so the stored order is the sample order.
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 3
        fields.imageHeight = 2
        fields.frameCount  = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 10, 20, 30, 40, 50, 60 ] ], timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == [ 10, 20, 30, 40, 50, 60 ] )
    }

    @Test
    func decodesSixteenBitSamplesLittleEndian() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.littleEndian       = 1
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 0x34, 0x12, 0x78, 0x56 ] ], timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == [ 0x1234, 0x5678 ] )
    }

    @Test
    func decodesSixteenBitSamplesBigEndian() async throws
    {
        // Field 4 is named `LittleEndian`, and reads 0 for big-endian 16-bit
        // image data.
        var fields = TestUtilities.wellFormedHeader

        fields.littleEndian       = 0
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 0x34, 0x12, 0x78, 0x56 ] ], timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == [ 0x3412, 0x7856 ] )
    }

    @Test
    func decodesSixteenBitSamplesAsUnsigned() async throws
    {
        // The specification calls 16-bit image data an unsigned integer, so a
        // sample with its high bit set is a large positive value, not a negative
        // one.
        var fields = TestUtilities.wellFormedHeader

        fields.littleEndian       = 1
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 0x00, 0x80, 0xFF, 0xFF ] ], timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == [ 32768, 65535 ] )
    }

    @Test
    func decodesEveryDepthWithoutRescalingTheStoredValue() async throws
    {
        // Samples come back exactly as the file stores them, aligned as the
        // specification aligns them. Scaling is left to the stages that need it,
        // which read `sampleRange` to know what full scale is.
        try Self.depthBoundaries.forEach
        {
            var fields = TestUtilities.wellFormedHeader

            fields.imageWidth         = 1
            fields.imageHeight        = 1
            fields.pixelDepthPerPlane = $0.depth
            fields.frameCount         = 1

            let data = TestUtilities.File( header: fields, frames: [ $0.bytes ], timestamps: nil ).data
            let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

            #expect( try frame.samples == [ $0.sample ], "depth \( $0.depth ) decodes to the wrong value" )
        }
    }

    @Test
    func decodesPaddingBitsTheSpecificationSaysAreZero() async throws
    {
        // A 4-bit sample is stored `bbbb0000`, but nothing in the format records
        // whether a writer really zeroed the padding, and there is nothing to
        // validate it against. The byte is decoded as it stands, so a sample can
        // come back above `sampleRange` — which is why that range documents
        // itself as a bound to clamp against rather than one to trust.
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 4
        fields.frameCount         = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 0xFF, 0xF0 ] ], timestamps: nil ).data
        let file  = try SERFile( data: data, options: .strict )
        let frame = try file.frame( at: 0 )

        #expect( file.header.sampleRange == 0 ... 240 )
        #expect( try frame.samples       == [ 255, 240 ] )
    }

    @Test
    func decodesOneSampleForEveryPlaneOfEveryPixel() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 0
        fields.imageWidth  = 4
        fields.imageHeight = 2
        fields.frameCount  = 1

        let mono = TestUtilities.File( header: fields, frames: [ [ UInt8 ]( repeating: 1, count: 8 ) ], timestamps: nil ).data

        fields.colorID = 100

        let rgb = TestUtilities.File( header: fields, frames: [ [ UInt8 ]( repeating: 1, count: 24 ) ], timestamps: nil ).data

        #expect( try SERFile( data: mono, options: .strict ).frame( at: 0 ).samples.count == 8 )
        #expect( try SERFile( data: rgb,  options: .strict ).frame( at: 0 ).samples.count == 24 )
    }

    // MARK: - Channel order

    @Test
    func keepsTheRGBChannelOrder() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 100
        fields.imageWidth  = 2
        fields.imageHeight = 1
        fields.frameCount  = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4, 5, 6 ] ], timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == [ 1, 2, 3, 4, 5, 6 ] )
    }

    @Test
    func reordersBGRToRGB() async throws
    {
        // BGR frames store [B][G][R]; everything downstream must see RGB.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 101
        fields.imageWidth  = 2
        fields.imageHeight = 1
        fields.frameCount  = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4, 5, 6 ] ], timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == [ 3, 2, 1, 6, 5, 4 ] )
    }

    @Test
    func reordersBGRToRGBAtSixteenBits() async throws
    {
        // Each channel occupies two bytes, so the swap moves samples, not bytes.
        let bytes = [ [ UInt8 ]( [ 0x01, 0x00, 0x02, 0x00, 0x03, 0x00 ] ) ]
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 101
        fields.littleEndian       = 1
        fields.imageWidth         = 1
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = Int32( bytes.count )

        let data = TestUtilities.File( header: fields, frames: bytes, timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == [ 3, 2, 1 ] )
    }

    @Test
    func leavesASinglePlaneMosaicAlone() async throws
    {
        // A Bayer frame is one plane, so no channel reordering applies to it.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 8
        fields.imageWidth  = 2
        fields.imageHeight = 2
        fields.frameCount  = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4 ] ], timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == [ 1, 2, 3, 4 ] )
    }

    // MARK: - Decoding paths

    @Test
    func acceleratedAndScalarPathsAgree() async throws
    {
        // Both implementations are always compiled, and only one of them is used
        // by default, so their equivalence has to be asserted rather than
        // assumed.
        try Self.decodingPathCases.forEach
        {
            let frame       = try SERFile( data: $0.data, options: .strict ).frame( at: 0 )
            let accelerated = try frame.decodedSamples( accelerated: true )
            let scalar      = try frame.decodedSamples( accelerated: false )

            #expect( accelerated == scalar,        "\( $0.name ) disagrees between the two paths" )
            #expect( accelerated.isEmpty == false, "\( $0.name ) decodes to nothing" )
        }
    }

    @Test
    func reordersBGRToRGBAtSixteenBitsBigEndian() async throws
    {
        // The byte swap and the channel swap are separate transformations, and
        // this is the one case where both apply at once.
        let bytes = [ [ UInt8 ]( [ 0x00, 0x01, 0x00, 0x02, 0x00, 0x03 ] ) ]
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 101
        fields.littleEndian       = 0
        fields.imageWidth         = 1
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = Int32( bytes.count )

        let data = TestUtilities.File( header: fields, frames: bytes, timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == [ 3, 2, 1 ] )
    }

    @Test
    func decodesFramesFromASlicedInput() async throws
    {
        // A file parsed from a slice addresses its frames relative to the
        // slice's own start, not to index zero.
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 1
        fields.frameCount  = 2

        let file = TestUtilities.File( header: fields, frames: [ [ 1, 2 ], [ 3, 4 ] ], timestamps: nil ).data
        let slice = ( Data( repeating: 0xAB, count: 64 ) + file ).dropFirst( 64 )

        #expect( slice.startIndex == 64 )

        let parsed = try SERFile( data: slice, options: .strict )

        #expect( parsed.frameCount                   == 2 )
        #expect( try parsed.frame( at: 0 ).samples   == [ 1, 2 ] )
        #expect( try parsed.frame( at: 1 ).samples   == [ 3, 4 ] )
    }

    @Test
    func decodingIsRepeatable() async throws
    {
        // Samples are decoded on each access rather than cached, so two reads of
        // the same frame must agree.
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 2
        fields.frameCount  = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 9, 8, 7, 6 ] ], timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( try frame.samples == frame.samples )
    }

    // MARK: - Short data

    @Test
    func throwsWhenTheFrameDataIsShort() async throws
    {
        // A file parsed by `SERFile` always holds every frame it reports, so this
        // is only reachable by building a frame by hand — but it must be an error
        // rather than a trap or a silently truncated result.
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 2

        let header = try SERHeader( data: fields.data, options: .strict )
        let frame  = SERFrame( index: 0, header: header, timestamp: nil, rawData: Data( [ 1, 2 ] ) )

        try #require( throws: SERError.self ) { try frame.samples }
        try #require( throws: SERError.self ) { try frame.decodedSamples( accelerated: false ) }
    }

    @Test
    func decodesAFrameHoldingExactlyItsBytes() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 2

        let header = try SERHeader( data: fields.data, options: .strict )
        let frame  = SERFrame( index: 0, header: header, timestamp: nil, rawData: Data( [ 1, 2, 3, 4 ] ) )

        #expect( try frame.samples == [ 1, 2, 3, 4 ] )
    }

    // MARK: - Timestamps

    @Test
    func carriesItsTimestampWhenTheFileHasATrailer() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 2
        fields.frameCount  = 2
        fields.dateTime    = Self.startTicks
        fields.dateTimeUTC = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4 ], [ 5, 6, 7, 8 ] ], timestamps: [ Self.startTicks, Self.startTicks + SERTimestamp.ticksPerSecond ] ).data

        let file = try SERFile( data: data, options: .strict )

        #expect( try file.frame( at: 0 ).timestamp == Self.startDate )
        #expect( try file.frame( at: 1 ).timestamp == Self.startDate.addingTimeInterval( 1 ) )
    }

    @Test
    func hasNoTimestampWithoutATrailer() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 2
        fields.frameCount  = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4 ] ], timestamps: nil ).data
        let file = try SERFile( data: data, options: .strict )

        #expect( try file.frame( at: 0 ).timestamp == nil )
    }

    @Test
    func aFrameAndTheFileAgreeOnEveryTimestamp() async throws
    {
        // A frame reads its own trailer entry, while `timestamps` parses the
        // whole trailer, so the two are separate readers of the same bytes and
        // have to agree — including where a short trailer stops.
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 2
        fields.frameCount  = 3
        fields.dateTime    = Self.startTicks
        fields.dateTimeUTC = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4 ], [ 5, 6, 7, 8 ], [ 9, 10, 11, 12 ] ], timestamps: [ Self.startTicks, Self.startTicks + SERTimestamp.ticksPerSecond ] ).data

        let file = try SERFile( data: data, options: .allowShortTrailer )

        #expect( file.frames.map { $0.timestamp } == file.timestamps )
        #expect( file.timestamps.count            == 3 )
    }

    // MARK: - Description

    @Test
    func descriptionSummarizesTheFrame() async throws
    {
        // Each row is rendered from a different quantity, so they are given
        // different values here: a description reading the wrong one would
        // otherwise go unnoticed.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 100
        fields.imageWidth         = 5
        fields.imageHeight        = 4
        fields.pixelDepthPerPlane = 12
        fields.frameCount         = 2
        fields.dateTime           = Self.startTicks
        fields.dateTimeUTC        = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: [ [ UInt8 ]( repeating: 0, count: 120 ), [ UInt8 ]( repeating: 0, count: 120 ) ], timestamps: [ Self.startTicks, Self.startTicks + SERTimestamp.ticksPerSecond ] ).data

        let file        = try SERFile( data: data, options: .strict )
        let frame       = try file.frame( at: 1 )
        let description = frame.description
        let timestamp   = try #require( frame.timestamp )

        #expect( description.contains( "SERFrame" ) )
        #expect( description.contains( "Index:     1" ) )
        #expect( description.contains( "Timestamp: \( timestamp )" ) )
        #expect( description.contains( "Bytes:     120" ) )
        #expect( description.contains( "Samples:   60" ) )
    }

    @Test
    func descriptionReportsAnAbsentTimestamp() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 2
        fields.frameCount  = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4 ] ], timestamps: nil ).data
        let frame = try SERFile( data: data, options: .strict ).frame( at: 0 )

        #expect( frame.description.contains( "Timestamp: Unknown" ) )
    }

    @Test
    func hasNoTimestampWhereAShortTrailerStops() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 2
        fields.frameCount  = 2
        fields.dateTime    = Self.startTicks
        fields.dateTimeUTC = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4 ], [ 5, 6, 7, 8 ] ], timestamps: [ Self.startTicks ] ).data

        let file = try SERFile( data: data, options: .allowShortTrailer )

        #expect( try file.frame( at: 0 ).timestamp == Self.startDate )
        #expect( try file.frame( at: 1 ).timestamp == nil )
    }
}
