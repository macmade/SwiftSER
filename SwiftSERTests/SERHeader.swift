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
        var nonPrintable = TestUtilities.headerData()

        nonPrintable[ TestUtilities.HeaderOffset.observer ] = 0x01

        return [
            ( "file ID",     TestUtilities.headerData( fileID: "NOT-A-SER-FILE" ), .allowInvalidFileID ),
            ( "color ID",    TestUtilities.headerData( colorID: 42 ),              .allowUnknownColorID ),
            ( "pixel depth", TestUtilities.headerData( pixelDepthPerPlane: 17 ),   .allowOutOfRangePixelDepth ),
            ( "name field",  nonPrintable,                                         .allowNonPrintableStrings ),
        ]
    }

    @Test
    func headerSizeIsFixedAtOneHundredSeventyEightBytes() async throws
    {
        #expect( SERHeader.size                   == 178 )
        #expect( TestUtilities.headerData().count == 178 )
    }

    @Test
    func parsesEveryField() async throws
    {
        let data = TestUtilities.headerData(
            fileID:             "LUCAM-RECORDER",
            luID:               7,
            colorID:            8,
            littleEndian:       1,
            imageWidth:         640,
            imageHeight:        480,
            pixelDepthPerPlane: 12,
            frameCount:         25,
            observer:           "Jean-David Gadina",
            instrument:         "ASI290MM",
            telescope:          "Newton 200/1000",
            dateTime:           635_000_000_000_000_000,
            dateTimeUTC:        635_000_000_000_000_001
        )

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
        var data = TestUtilities.headerData()

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
        let data   = TestUtilities.headerData( littleEndian: 0, imageWidth: 0x0102 )
        let header = try SERHeader( data: data, options: .strict )

        #expect( header.isLittleEndian == false )
        #expect( header.imageWidth     == 0x0102 )
    }

    @Test
    func byteOrderFlagIsReadAsABoolean() async throws
    {
        #expect( try SERHeader( data: TestUtilities.headerData( littleEndian: 1 ), options: .strict ).isLittleEndian == true )
        #expect( try SERHeader( data: TestUtilities.headerData( littleEndian: 0 ), options: .strict ).isLittleEndian == false )
    }

    @Test
    func acceptsDataLongerThanTheHeader() async throws
    {
        // The header is parsed from the front of the whole file, not from an
        // exactly-sized buffer.
        let data   = TestUtilities.headerData() + Data( repeating: 0xFF, count: 1024 )
        let header = try SERHeader( data: data, options: .strict )

        #expect( header.fileID == "LUCAM-RECORDER" )
    }

    @Test
    func rejectsTruncatedData() async throws
    {
        let data = TestUtilities.headerData().prefix( 177 )

        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .lenient ) }
        try #require( throws: SERError.self ) { try SERHeader( data: Data(), options: .lenient ) }
    }

    @Test
    func honorsANonZeroBasedSlice() async throws
    {
        // The whole-file data handed down by `SERFile` may itself be a slice.
        let full   = Data( repeating: 0xFF, count: 64 ) + TestUtilities.headerData( imageWidth: 320 )
        let header = try SERHeader( data: full[ 64... ], options: .strict )

        #expect( header.imageWidth == 320 )
    }

    // MARK: - Derived geometry

    @Test
    func numberOfPlanesFollowsTheColorID() async throws
    {
        #expect( try SERHeader( data: TestUtilities.headerData( colorID: 0   ), options: .strict ).numberOfPlanes == 1 )
        #expect( try SERHeader( data: TestUtilities.headerData( colorID: 11  ), options: .strict ).numberOfPlanes == 1 )
        #expect( try SERHeader( data: TestUtilities.headerData( colorID: 100 ), options: .strict ).numberOfPlanes == 3 )
        #expect( try SERHeader( data: TestUtilities.headerData( colorID: 101 ), options: .strict ).numberOfPlanes == 3 )
    }

    @Test
    func bytesPerPixelFollowsTheDepthBands() async throws
    {
        // 1..8 bits occupy one byte per plane, 9..16 two.
        try [ ( depth: Int32( 1 ), bytes: 1 ), ( 8, 1 ), ( 9, 2 ), ( 16, 2 ) ].forEach
        {
            let mono = try SERHeader( data: TestUtilities.headerData( colorID: 0,   pixelDepthPerPlane: $0.depth ), options: .strict )
            let rgb  = try SERHeader( data: TestUtilities.headerData( colorID: 100, pixelDepthPerPlane: $0.depth ), options: .strict )

            #expect( mono.bytesPerPixel == $0.bytes,     "depth \( $0.depth ) is misclassified for MONO" )
            #expect( rgb.bytesPerPixel  == $0.bytes * 3, "depth \( $0.depth ) is misclassified for RGB" )
        }
    }

    @Test
    func bytesPerFrameMultipliesTheGeometry() async throws
    {
        let mono = try SERHeader( data: TestUtilities.headerData( colorID: 0, imageWidth: 640, imageHeight: 480, pixelDepthPerPlane: 16 ), options: .strict )
        let rgb  = try SERHeader( data: TestUtilities.headerData( colorID: 100, imageWidth: 640, imageHeight: 480, pixelDepthPerPlane: 8 ), options: .strict )

        #expect( mono.bytesPerFrame == 640 * 480 * 2 )
        #expect( rgb.bytesPerFrame  == 640 * 480 * 3 )
    }

    @Test
    func rejectsGeometryThatWouldOverflow() async throws
    {
        // A corrupt header must not produce a trap or a wrapped frame size.
        let data = TestUtilities.headerData( colorID: 100, imageWidth: Int32.max, imageHeight: Int32.max, pixelDepthPerPlane: 16 )

        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .lenient ) }
    }

    @Test
    func bayerPatternFollowsTheColorID() async throws
    {
        #expect( try SERHeader( data: TestUtilities.headerData( colorID: 8   ), options: .strict ).bayerPattern == .rggb )
        #expect( try SERHeader( data: TestUtilities.headerData( colorID: 19  ), options: .strict ).bayerPattern == .myyc )
        #expect( try SERHeader( data: TestUtilities.headerData( colorID: 0   ), options: .strict ).bayerPattern == nil )
        #expect( try SERHeader( data: TestUtilities.headerData( colorID: 100 ), options: .strict ).bayerPattern == nil )
    }

    @Test
    func timestampTrailerPresenceFollowsTheStartDate() async throws
    {
        // A start date of zero or less is invalid, and the specification says
        // such a file carries no trailer.
        #expect( try SERHeader( data: TestUtilities.headerData( dateTime:  1 ), options: .strict ).declaresTimestampTrailer == true )
        #expect( try SERHeader( data: TestUtilities.headerData( dateTime:  0 ), options: .strict ).declaresTimestampTrailer == false )
        #expect( try SERHeader( data: TestUtilities.headerData( dateTime: -1 ), options: .strict ).declaresTimestampTrailer == false )
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
        let data = TestUtilities.headerData( fileID: "NOT-A-SER-FILE" )

        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .strict ) }

        let header = try SERHeader( data: data, options: .lenient )

        #expect( header.fileID == "NOT-A-SER-FILE" )
    }

    @Test
    func rejectsAPixelDepthOutsideTheSpecifiedRange() async throws
    {
        try [ Int32( 0 ), 17, -1, 32 ].forEach
        {
            let data = TestUtilities.headerData( pixelDepthPerPlane: $0 )

            try #require( throws: SERError.self ) { try SERHeader( data: data, options: .strict ) }

            #expect( try SERHeader( data: data, options: .lenient ).pixelDepthPerPlane == $0 )
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
            let header = try SERHeader( data: TestUtilities.headerData( pixelDepthPerPlane: $0.depth ), options: .lenient )

            #expect( header.bytesPerPixel == $0.bytes, "depth \( $0.depth ) is sized wrong" )
        }
    }

    @Test
    func acceptsEveryDepthBoundary() async throws
    {
        try [ Int32( 1 ), 8, 9, 16 ].forEach
        {
            let header = try SERHeader( data: TestUtilities.headerData( pixelDepthPerPlane: $0 ), options: .strict )

            #expect( header.pixelDepthPerPlane == $0 )
        }
    }

    @Test
    func rejectsAnUnknownColorID() async throws
    {
        let data = TestUtilities.headerData( colorID: 42 )

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
            let data = TestUtilities.headerData( imageWidth: $0.width, imageHeight: $0.height )

            try #require( throws: SERError.self ) { try SERHeader( data: data, options: .strict ) }
            try #require( throws: SERError.self ) { try SERHeader( data: data, options: .lenient ) }
        }
    }

    @Test
    func rejectsANegativeFrameCountUnderEveryOption() async throws
    {
        let data = TestUtilities.headerData( frameCount: -1 )

        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .strict ) }
        try #require( throws: SERError.self ) { try SERHeader( data: data, options: .lenient ) }
    }

    @Test
    func acceptsAnEmptySequence() async throws
    {
        let header = try SERHeader( data: TestUtilities.headerData( frameCount: 0 ), options: .strict )

        #expect( header.frameCount == 0 )
    }

    // MARK: - Strings

    @Test
    func trimsStringsAtTheFirstNulByte() async throws
    {
        // Unused characters are filled with 0, so the first NUL ends the text.
        var data = TestUtilities.headerData( observer: "Observer" )

        data[ TestUtilities.HeaderOffset.observer + 3 ] = 0

        let header = try SERHeader( data: data, options: .strict )

        #expect( header.observer == "Obs" )
    }

    @Test
    func readsAFullyOccupiedStringField() async throws
    {
        // Forty characters leave no room for a terminating NUL.
        let name   = String( repeating: "A", count: 40 )
        let header = try SERHeader( data: TestUtilities.headerData( observer: name ), options: .strict )

        #expect( header.observer == name )
    }

    @Test
    func readsAnEmptyStringField() async throws
    {
        let header = try SERHeader( data: TestUtilities.headerData( observer: "" ), options: .strict )

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
            var data = TestUtilities.headerData()

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
            var data = TestUtilities.headerData()

            data[ TestUtilities.HeaderOffset.telescope ] = $0

            try #require( throws: SERError.self, "byte \( $0 ) must be rejected" ) { try SERHeader( data: data, options: .strict ) }
            _ = try SERHeader( data: data, options: .lenient )
        }
    }

    @Test
    func acceptsThePrintableBoundaries() async throws
    {
        var data = TestUtilities.headerData()

        data[ TestUtilities.HeaderOffset.observer     ] = 0x20
        data[ TestUtilities.HeaderOffset.observer + 1 ] = 0x7E

        let header = try SERHeader( data: data, options: .strict )

        #expect( header.observer.hasPrefix( " ~" ) )
    }

    // MARK: - Description

    @Test
    func descriptionSummarizesTheHeader() async throws
    {
        let header      = try SERHeader( data: TestUtilities.headerData( colorID: 8, imageWidth: 640, imageHeight: 480 ), options: .strict )
        let description = header.description

        #expect( description.contains( "SERHeader" ) )
        #expect( description.contains( "LUCAM-RECORDER" ) )
        #expect( description.contains( "BAYER_RGGB" ) )
        #expect( description.contains( "640" ) )
        #expect( description.contains( "480" ) )
    }
}
