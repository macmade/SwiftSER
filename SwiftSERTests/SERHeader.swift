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

struct Test_SERHeader
{
    /// Each validation the header performs, with a file that trips it and the
    /// single leniency flag meant to wave it through.
    static var gatedValidations: [ ( name: String, data: Data, flag: SERParsingOptions ) ]
    {
        var nonPrintable = TestUtilities.wellFormedHeader.data

        nonPrintable[ TestUtilities.HeaderOffset.observer ] = 0x01

        return [
            ( "file ID",     TestUtilities.wellFormedHeader.changing { $0.fileID = "NOT-A-SER-FILE" }.data, .allowInvalidFileID ),
            ( "color ID",    TestUtilities.wellFormedHeader.changing { $0.colorID = 42 }.data,              .allowUnknownColorID ),
            ( "pixel depth", TestUtilities.wellFormedHeader.changing { $0.pixelDepthPerPlane = 17 }.data,   .allowOutOfRangePixelDepth ),
            ( "name field",  nonPrintable,                                         .allowNonPrintableStrings ),
        ]
    }

    /// The byte width a sample occupies at each depth band boundary.
    static let sampleWidths: [ ( depth: Int32, bytes: Int ) ] = [
        ( 1,  1 ),
        ( 8,  1 ),
        ( 9,  2 ),
        ( 16, 2 ),
    ]

    /// The largest value a sample can hold at each depth the specification
    /// defines, following its two alignment rules.
    static let sampleRanges: [ ( depth: Int32, maximum: Double ) ] = [
        ( 1,  128.0 ),
        ( 2,  192.0 ),
        ( 5,  248.0 ),
        ( 7,  254.0 ),
        ( 8,  255.0 ),
        ( 9,  511.0 ),
        ( 12, 4095.0 ),
        ( 16, 65535.0 ),
    ]

    /// The largest value a sample can hold at a depth the specification does
    /// not define, which is the widest one of the byte band it lands in.
    static let outOfRangeSampleRanges: [ ( depth: Int32, maximum: Double ) ] = [
        ( -5, 255.0 ),
        ( 0,  255.0 ),
        ( 17, 65535.0 ),
        ( 32, 65535.0 ),
    ]

    @Test
    func headerSizeIsFixedAtOneHundredSeventyEightBytes() async throws
    {
        #expect( SERHeader.size                   == 178 )
        #expect( TestUtilities.wellFormedHeader.data.count == 178 )
    }

    @Test
    func parsesEveryField() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.fileID             = "LUCAM-RECORDER"
        fields.luID               = 7
        fields.colorID            = 8
        fields.littleEndian       = 1
        fields.imageWidth         = 640
        fields.imageHeight        = 480
        fields.pixelDepthPerPlane = 12
        fields.frameCount         = 25
        fields.observer           = "Jean-David Gadina"
        fields.instrument         = "ASI290MM"
        fields.telescope          = "Newton 200/1000"
        fields.dateTime           = 635_000_000_000_000_000
        fields.dateTimeUTC        = 635_000_000_000_000_001

        let data = fields.data

        let header = try SERHeader( data: data, options: .strict )

        #expect( header.fileID             == "LUCAM-RECORDER" )
        #expect( header.luID               == 7 )
        #expect( header.colorID            == .bayerRGGB )
        #expect( header.isLittleEndian     == true )
        #expect( header.imageWidth         == 640 )
        #expect( header.imageHeight        == 480 )
        #expect( header.pixelDepthPerPlane == 12 )
        #expect( header.frameCount         == 25 )
        #expect( header.observer           == "Jean-David Gadina" )
        #expect( header.instrument         == "ASI290MM" )
        #expect( header.telescope          == "Newton 200/1000" )
        #expect( header.dateTime           == 635_000_000_000_000_000 )
        #expect( header.dateTimeUTC        == 635_000_000_000_000_001 )
    }

    @Test
    func decodesFieldsAtTheSpecifiedOffsets() async throws
    {
        // The specification lists field lengths but not absolute offsets, so the
        // offsets are derived. Writing a value straight into the byte range each
        // field is expected to occupy proves the derivation.
        var data = TestUtilities.wellFormedHeader.data

        TestUtilities.littleEndianBytes( Int32( 0x11223344 ) ).enumerated().forEach
        {
            data[ TestUtilities.HeaderOffset.imageWidth + $0.offset ] = $0.element
        }

        TestUtilities.littleEndianBytes( Int64( 0x1122334455667788 ) ).enumerated().forEach
        {
            data[ TestUtilities.HeaderOffset.dateTimeUTC + $0.offset ] = $0.element
        }

        let header = try SERHeader( data: data, options: .lenient )

        #expect( header.imageWidth  == 0x11223344 )
        #expect( header.dateTimeUTC == 0x1122334455667788 )
    }

    @Test
    func headerFieldsAreAlwaysLittleEndian() async throws
    {
        // Field 4 governs the byte order of 16-bit image data only. The header's
        // own integers are little-endian whatever it says.
        var fields = TestUtilities.wellFormedHeader

        fields.littleEndian = 0
        fields.imageWidth   = 0x0102

        let data = fields.data
        let header = try SERHeader( data: data, options: .strict )

        #expect( header.isLittleEndian == false )
        #expect( header.imageWidth     == 0x0102 )
    }

    @Test
    func byteOrderFlagIsReadAsABoolean() async throws
    {
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.littleEndian = 1 }.data, options: .strict ).isLittleEndian == true )
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.littleEndian = 0 }.data, options: .strict ).isLittleEndian == false )
    }

    @Test
    func acceptsDataLongerThanTheHeader() async throws
    {
        // The header is parsed from the front of the whole file, not from an
        // exactly-sized buffer.
        let data   = TestUtilities.wellFormedHeader.data + Data( repeating: 0xFF, count: 1024 )
        let header = try SERHeader( data: data, options: .strict )

        #expect( header.fileID == "LUCAM-RECORDER" )
    }

    @Test
    func rejectsTruncatedData() async throws
    {
        let data = TestUtilities.wellFormedHeader.data.prefix( 177 )

        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .lenient ) }
        try #require( throws: SERError.self ) { try SERHeader( data: Data(), options: .lenient ) }
    }

    @Test
    func honorsANonZeroBasedSlice() async throws
    {
        // The whole-file data handed down by `SERFile` may itself be a slice.
        let full   = Data( repeating: 0xFF, count: 64 ) + TestUtilities.wellFormedHeader.changing { $0.imageWidth = 320 }.data
        let header = try SERHeader( data: full[ 64... ], options: .strict )

        #expect( header.imageWidth == 320 )
    }

    // MARK: - Derived geometry

    @Test
    func numberOfPlanesFollowsTheColorID() async throws
    {
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.colorID = 0 }.data, options: .strict ).numberOfPlanes == 1 )
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.colorID = 11 }.data, options: .strict ).numberOfPlanes == 1 )
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.colorID = 100 }.data, options: .strict ).numberOfPlanes == 3 )
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.colorID = 101 }.data, options: .strict ).numberOfPlanes == 3 )
    }

    @Test
    func bytesPerPixelFollowsTheDepthBands() async throws
    {
        // 1..8 bits occupy one byte per plane, 9..16 two.
        try [ ( depth: Int32( 1 ), bytes: 1 ), ( 8, 1 ), ( 9, 2 ), ( 16, 2 ) ].forEach
        {
            width in

            var fields = TestUtilities.wellFormedHeader

            fields.colorID            = 0
            fields.pixelDepthPerPlane = width.depth

            let mono = try SERHeader( data: fields.data, options: .strict )

            fields.colorID = 100

            let rgb = try SERHeader( data: fields.data, options: .strict )

            #expect( mono.bytesPerPixel == width.bytes,     "depth \( width.depth ) is misclassified for MONO" )
            #expect( rgb.bytesPerPixel  == width.bytes * 3, "depth \( width.depth ) is misclassified for RGB" )
        }
    }

    @Test
    func bytesPerFrameMultipliesTheGeometry() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 640
        fields.imageHeight        = 480
        fields.pixelDepthPerPlane = 16

        let mono = try SERHeader( data: fields.data, options: .strict )

        fields.colorID            = 100
        fields.pixelDepthPerPlane = 8

        let rgb = try SERHeader( data: fields.data, options: .strict )

        #expect( mono.bytesPerFrame == 640 * 480 * 2 )
        #expect( rgb.bytesPerFrame  == 640 * 480 * 3 )
    }

    @Test
    func everySampleGeometryTableIsListed() async throws
    {
        // The three tests below iterate these tables, so a row dropped from one
        // would leave them passing while proving less.
        #expect( Self.sampleWidths.map { $0.depth }              == [ 1, 8, 9, 16 ] )
        #expect( Self.sampleRanges.map { $0.depth }              == [ 1, 2, 5, 7, 8, 9, 12, 16 ] )
        #expect( Self.outOfRangeSampleRanges.map { $0.depth }    == [ -5, 0, 17, 32 ] )
    }

    @Test
    func bytesPerSampleFollowsTheDepthBands() async throws
    {
        // A sample's own width, before the planes a pixel interleaves.
        try Self.sampleWidths.forEach
        {
            width in

            var fields = TestUtilities.wellFormedHeader

            fields.colorID            = 0
            fields.pixelDepthPerPlane = width.depth

            let mono = try SERHeader( data: fields.data, options: .strict )

            fields.colorID = 100

            let rgb = try SERHeader( data: fields.data, options: .strict )

            #expect( mono.bytesPerSample == width.bytes, "depth \( width.depth ) is misclassified for MONO" )
            #expect( rgb.bytesPerSample  == width.bytes, "depth \( width.depth ) is misclassified for RGB" )
        }
    }

    @Test
    func samplesPerFrameCountsEveryPlane() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 4
        fields.imageHeight        = 2
        fields.pixelDepthPerPlane = 16

        let mono = try SERHeader( data: fields.data, options: .strict )

        fields.colorID            = 100
        fields.pixelDepthPerPlane = 8

        let rgb = try SERHeader( data: fields.data, options: .strict )

        fields.colorID            = 8
        fields.pixelDepthPerPlane = 12

        let mosaic = try SERHeader( data: fields.data, options: .strict )

        // The sample count is independent of a sample's width, unlike the byte
        // count, so the depths above deliberately differ.
        #expect( mono.samplesPerFrame   == 4 * 2 )
        #expect( rgb.samplesPerFrame    == 4 * 2 * 3 )
        #expect( mosaic.samplesPerFrame == 4 * 2 )
    }

    @Test
    func sampleRangeFollowsTheAlignmentRules() async throws
    {
        // Depths of 1 to 8 are stored MSB-aligned within a byte, so their
        // largest value is left-shifted toward full scale; depths of 9 to 16 are
        // LSB-aligned within two bytes and stop at 2^depth - 1.
        try Self.sampleRanges.forEach
        {
            range in

            let header = try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.pixelDepthPerPlane = range.depth }.data, options: .strict )

            #expect( header.sampleRange == 0 ... range.maximum, "depth \( range.depth ) has the wrong sample range" )
        }
    }

    @Test
    func sampleRangeForcesAnOutOfRangeDepthIntoItsBand() async throws
    {
        // A depth the specification does not define has no range of its own, so
        // it takes the widest one of the band its byte width was forced into.
        // Narrowing it instead would advertise a bound the file's own bytes are
        // free to exceed.
        try Self.outOfRangeSampleRanges.forEach
        {
            range in

            let header = try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.pixelDepthPerPlane = range.depth }.data, options: .allowOutOfRangePixelDepth )

            #expect( header.sampleRange == 0 ... range.maximum, "depth \( range.depth ) has the wrong sample range" )
        }
    }

    @Test
    func rejectsGeometryThatWouldOverflow() async throws
    {
        // A corrupt header must not produce a trap or a wrapped frame size.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 100
        fields.imageWidth         = Int32.max
        fields.imageHeight        = Int32.max
        fields.pixelDepthPerPlane = 16

        let data = fields.data

        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .lenient ) }
    }

    @Test
    func bayerPatternFollowsTheColorID() async throws
    {
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.colorID = 8 }.data, options: .strict ).bayerPattern == .rggb )
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.colorID = 19 }.data, options: .strict ).bayerPattern == .myyc )
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.colorID = 0 }.data, options: .strict ).bayerPattern == nil )
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.colorID = 100 }.data, options: .strict ).bayerPattern == nil )
    }

    @Test
    func timestampTrailerPresenceFollowsTheStartDate() async throws
    {
        // A start date of zero or less is invalid, and the specification says
        // such a file carries no trailer.
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.dateTime = 1 }.data, options: .strict ).declaresTimestampTrailer == true )
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.dateTime = 0 }.data, options: .strict ).declaresTimestampTrailer == false )
        #expect( try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.dateTime = -1 }.data, options: .strict ).declaresTimestampTrailer == false )
    }

    // MARK: - Validation

    @Test
    func everyGatedValidationIsListed() async throws
    {
        // The two tests below iterate this table, so a row dropped from it would
        // leave them passing while proving nothing.
        #expect( Self.gatedValidations.map { $0.flag } == [ .allowInvalidFileID, .allowUnknownColorID, .allowOutOfRangePixelDepth, .allowNonPrintableStrings ] )
    }

    @Test
    func eachValidationIsWaivedByItsOwnFlagAlone() async throws
    {
        try Self.gatedValidations.forEach
        {
            _ = try SERHeader( data: $0.data, options: $0.flag )
        }
    }

    @Test
    func eachValidationSurvivesEveryOtherFlag() async throws
    {
        // Withdrawing one flag from the lenient preset must bring back exactly
        // one rejection. Testing only through the two presets would let a
        // validation wired to the wrong flag pass unnoticed, since strict sets
        // none of them and lenient sets them all.
        try Self.gatedValidations.forEach
        {
            validation in

            let options = SERParsingOptions.lenient.subtracting( validation.flag )

            try #require( throws: SERError.self, "the \( validation.name ) check is not gated by its own flag" ) { try SERHeader( data: validation.data, options: options ) }
        }
    }

    @Test
    func rejectsAnInvalidFileID() async throws
    {
        let data = TestUtilities.wellFormedHeader.changing { $0.fileID = "NOT-A-SER-FILE" }.data

        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .strict ) }

        let header = try SERHeader( data: data, options: .lenient )

        #expect( header.fileID == "NOT-A-SER-FILE" )
    }

    @Test
    func rejectsAPixelDepthOutsideTheSpecifiedRange() async throws
    {
        try [ Int32( 0 ), 17, -1, 32 ].forEach
        {
            depth in

            let data = TestUtilities.wellFormedHeader.changing { $0.pixelDepthPerPlane = depth }.data

            try #require( throws: SERError.self ) { try SERHeader( data: data, options: .strict ) }

            #expect( try SERHeader( data: data, options: .lenient ).pixelDepthPerPlane == depth )
        }
    }

    @Test
    func clampsBytesPerPixelForDepthsOutsideTheSpecifiedRange() async throws
    {
        // Such a depth has no width of its own, so it is forced into one of the
        // two defined bands rather than given a size the specification never
        // assigns it.
        try [ ( depth: Int32( 0 ), bytes: 1 ), ( -5, 1 ), ( 17, 2 ), ( 32, 2 ) ].forEach
        {
            band in

            let header = try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.pixelDepthPerPlane = band.depth }.data, options: .lenient )

            #expect( header.bytesPerPixel == band.bytes, "depth \( band.depth ) is sized wrong" )
        }
    }

    @Test
    func acceptsEveryDepthBoundary() async throws
    {
        try [ Int32( 1 ), 8, 9, 16 ].forEach
        {
            depth in

            let header = try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.pixelDepthPerPlane = depth }.data, options: .strict )

            #expect( header.pixelDepthPerPlane == depth )
        }
    }

    @Test
    func rejectsAnUnknownColorID() async throws
    {
        let data = TestUtilities.wellFormedHeader.changing { $0.colorID = 42 }.data

        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .strict ) }

        let header = try SERHeader( data: data, options: .lenient )

        #expect( header.colorID == .unknown( 42 ) )
    }

    @Test
    func rejectsNonPositiveDimensionsUnderEveryOption() async throws
    {
        // Neither preset can make sense of a frame with no extent: every derived
        // size would be zero or negative, so this is rejected outright rather
        // than tied to a leniency flag.
        try [ ( width: Int32( 0 ), height: Int32( 2 ) ), ( 4, 0 ), ( -1, 2 ), ( 4, -1 ) ].forEach
        {
            var fields = TestUtilities.wellFormedHeader

            fields.imageWidth  = $0.width
            fields.imageHeight = $0.height

            let data = fields.data

            try #require( throws: SERError.self ) { try SERHeader( data: data, options: .strict ) }
            try #require( throws: SERError.self ) { try SERHeader( data: data, options: .lenient ) }
        }
    }

    @Test
    func rejectsANegativeFrameCountUnderEveryOption() async throws
    {
        let data = TestUtilities.wellFormedHeader.changing { $0.frameCount = -1 }.data

        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .strict ) }
        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .lenient ) }
    }

    @Test
    func acceptsAnEmptySequence() async throws
    {
        let header = try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.frameCount = 0 }.data, options: .strict )

        #expect( header.frameCount == 0 )
    }

    // MARK: - Strings

    @Test
    func trimsStringsAtTheFirstNulByte() async throws
    {
        // Unused characters are filled with 0, so the first NUL ends the text.
        var data = TestUtilities.wellFormedHeader.changing { $0.observer = "Observer" }.data

        data[ TestUtilities.HeaderOffset.observer + 3 ] = 0

        let header = try SERHeader( data: data, options: .strict )

        #expect( header.observer == "Obs" )
    }

    @Test
    func readsAFullyOccupiedStringField() async throws
    {
        // Forty characters leave no room for a terminating NUL.
        let name   = String( repeating: "A", count: 40 )
        let header = try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.observer = name }.data, options: .strict )

        #expect( header.observer == name )
    }

    @Test
    func readsAnEmptyStringField() async throws
    {
        let header = try SERHeader( data: TestUtilities.wellFormedHeader.changing { $0.observer = "" }.data, options: .strict )

        #expect( header.observer.isEmpty )
    }

    @Test
    func rejectsNonPrintableStrings() async throws
    {
        try [
            ( offset: TestUtilities.HeaderOffset.observer,   name: "observer" ),
            ( offset: TestUtilities.HeaderOffset.instrument, name: "instrument" ),
            ( offset: TestUtilities.HeaderOffset.telescope,  name: "telescope" ),
        ]
        .forEach
        {
            var data = TestUtilities.wellFormedHeader.data

            data[ $0.offset ] = 0x01

            try #require( throws: SERError.self, "\( $0.name ) must be validated" ) { try SERHeader( data: data, options: .strict ) }
            _ = try SERHeader( data: data, options: .lenient )
        }
    }

    @Test
    func rejectsStringsOutsideThePrintableRange() async throws
    {
        // One byte past each end of the 0x20...0x7E range the specification
        // allows, so a boundary set one off is caught.
        try [ UInt8( 0x1F ), 0x7F ].forEach
        {
            var data = TestUtilities.wellFormedHeader.data

            data[ TestUtilities.HeaderOffset.telescope ] = $0

            try #require( throws: SERError.self, "byte \( $0 ) must be rejected" ) { try SERHeader( data: data, options: .strict ) }
            _ = try SERHeader( data: data, options: .lenient )
        }
    }

    @Test
    func acceptsThePrintableBoundaries() async throws
    {
        var data = TestUtilities.wellFormedHeader.data

        data[ TestUtilities.HeaderOffset.observer     ] = 0x20
        data[ TestUtilities.HeaderOffset.observer + 1 ] = 0x7E

        let header = try SERHeader( data: data, options: .strict )

        #expect( header.observer.hasPrefix( " ~" ) )
    }

    // MARK: - Description

    @Test
    func descriptionSummarizesTheHeader() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 8
        fields.imageWidth  = 640
        fields.imageHeight = 480

        let header      = try SERHeader( data: fields.data, options: .strict )
        let description = header.description

        #expect( description.contains( "SERHeader" ) )
        #expect( description.contains( "LUCAM-RECORDER" ) )
        #expect( description.contains( "BAYER_RGGB" ) )
        #expect( description.contains( "640" ) )
        #expect( description.contains( "480" ) )
    }

    @Test
    func descriptionListsEveryDerivedQuantity() async throws
    {
        // The description exists to summarize the header, so a derived value it
        // exposes and does not report is a gap. The geometry below is chosen so
        // that no two of these rows share a value.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 100
        fields.imageWidth         = 5
        fields.imageHeight        = 4
        fields.pixelDepthPerPlane = 12

        let header      = try SERHeader( data: fields.data, options: .strict )
        let description = header.description

        #expect( description.contains( "Number Of Planes:      3" ) )
        #expect( description.contains( "Bytes Per Sample:      2" ) )
        #expect( description.contains( "Bytes Per Pixel:       6" ) )
        #expect( description.contains( "Bytes Per Frame:       120" ) )
        #expect( description.contains( "Samples Per Frame:     60" ) )
        #expect( description.contains( "Sample Range:          0.0...4095.0" ) )
    }
}
