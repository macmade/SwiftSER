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

struct Test_SERFile
{
    /// A tick value naming a valid instant, so a file can declare a trailer.
    static let startTicks = Int64( 635_000_000_000_000_000 )

    // MARK: - Opening

    @Test
    func parsesACompleteFile() async throws
    {
        let file = try SERFile( data: TestUtilities.wellFormedHeader( frameCount: 3 ).file.data, options: .strict )

        #expect( file.header.imageWidth  == 4 )
        #expect( file.header.imageHeight == 2 )
        #expect( file.frameCount         == 3 )
    }

    @Test
    func rejectsDataTooShortForAHeader() async throws
    {
        try #require( throws: SERError.self ) { try SERFile( data: Data(), options: .lenient ) }
        try #require( throws: SERError.self ) { try SERFile( data: TestUtilities.wellFormedHeader.data.prefix( 100 ), options: .lenient ) }
    }

    @Test
    func acceptsAnEmptySequence() async throws
    {
        // A header declaring no frames is degenerate but well-formed.
        let file = try SERFile( data: TestUtilities.wellFormedHeader( frameCount: 0 ).file.data, options: .strict )

        #expect( file.frameCount == 0 )
        #expect( file.timestamps.isEmpty )
    }

    @Test
    func readsFromAFileURL() async throws
    {
        let url  = try TestUtilities.temporaryFile( containing: TestUtilities.wellFormedHeader( frameCount: 2 ).file.data, named: "capture.ser" )
        let file = try SERFile( url: url, options: .strict )

        #expect( file.frameCount == 2 )

        try FileManager.default.removeItem( at: url.deletingLastPathComponent() )
    }

    @Test
    func rejectsAMissingFileURL() async throws
    {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent( "\( UUID().uuidString ).ser" )

        try #require( throws: SERError.self ) { try SERFile( url: url, options: .lenient ) }
    }

    @Test
    func rejectsADirectoryURL() async throws
    {
        let url = FileManager.default.temporaryDirectory

        try #require( throws: SERError.self ) { try SERFile( url: url, options: .lenient ) }
    }

    // MARK: - Frame count reconciliation

    @Test
    func rejectsAFileShorterThanItsDeclaredFrames() async throws
    {
        // The header claims four frames but only two were written.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 4

        let frames = TestUtilities.indexedFrames( count: 2, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data

        try #require( throws: SERError.self ) { try SERFile( data: data, options: .strict ) }
    }

    @Test
    func clampsTheFrameCountToWhatThePayloadHolds() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 4

        let frames = TestUtilities.indexedFrames( count: 2, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data
        let file = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount        == 2 )
        #expect( file.header.frameCount == 4 )
    }

    @Test
    func clampingIsGatedByItsOwnFlag() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 4

        let frames = TestUtilities.indexedFrames( count: 2, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data
        let options = SERParsingOptions.lenient.subtracting( .allowFrameCountMismatch )

        try #require( throws: SERError.self ) { try SERFile( data: data, options: options ) }

        #expect( try SERFile( data: data, options: .allowFrameCountMismatch ).frameCount == 2 )
    }

    @Test
    func clampsAPartialTrailingFrame() async throws
    {
        // A capture cut mid-frame yields whole frames only, never a fragment.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 4

        let frames = TestUtilities.indexedFrames( count: 2, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data + Data( repeating: 0xFF, count: 3 )
        let file = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount == 2 )
    }

    @Test
    func clampingNeverAddressesTrailerBytesAsFrames() async throws
    {
        // The header over-declares, and the file carries a trailer. Dividing the
        // remaining bytes by the frame size alone would count the trailer's
        // bytes as frames and hand back a frame overlapping it.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 100
        fields.dateTime   = Self.startTicks

        let frames = TestUtilities.indexedFrames( count: 2, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: [ Self.startTicks, Self.startTicks + 10_000_000 ] ).data

        let file = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount          == 2 )
        #expect( file.hasTimestampTrailer == true )
        #expect( try file.byteOffset( ofFrame: 1 ) == 178 + 8 )

        try #require( throws: SERError.self ) { try file.byteOffset( ofFrame: 2 ) }
    }

    @Test
    func clampingKeepsEveryFrameOfACaptureCutBeforeItsTrailer() async throws
    {
        // The trailer is written last, so an interrupted capture has a valid
        // start date and no trailer at all. Assuming a trailer regardless would
        // swallow the final frame and read its pixels as timestamps.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 0
        fields.imageWidth  = 64
        fields.imageHeight = 48
        fields.frameCount  = 1000
        fields.dateTime    = Self.startTicks

        let frames = TestUtilities.indexedFrames( count: 10, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data
        let file = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount          == 10 )
        #expect( file.hasTimestampTrailer == false )
        #expect( file.timestamps          == [ Date? ]( repeating: nil, count: 10 ) )
    }

    @Test
    func clampingTellsAShortTrailerFromAnExtraFrame() async throws
    {
        // Two frames and a single timestamp. Every divisor-based reading of the
        // payload gets this wrong: dividing by the frame size alone comes out
        // at three frames, the third being the timestamp's bytes.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 100
        fields.dateTime   = Self.startTicks

        let frames = TestUtilities.indexedFrames( count: 2, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: [ Self.startTicks ] ).data
        let file = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount          == 2 )
        #expect( file.hasTimestampTrailer == true )

        try #require( file.timestamps.count == 2 )

        #expect( file.timestamps[ 0 ] != nil )
        #expect( file.timestamps[ 1 ] == nil )
    }

    @Test
    func clampingResolvesAPayloadThatFitsBothReadingsExactly() async throws
    {
        // 385 frames of 3072 bytes is exactly 384 frames plus 384 timestamps,
        // so the payload length alone cannot say which it is. There is no
        // trailer here, and every frame must survive.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 0
        fields.imageWidth  = 64
        fields.imageHeight = 48
        fields.frameCount  = 1000
        fields.dateTime    = Self.startTicks

        let frames = TestUtilities.indexedFrames( count: 385, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data
        let file = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount          == 385 )
        #expect( file.hasTimestampTrailer == false )
        #expect( file.timestamps.allSatisfy { $0 == nil } )
    }

    @Test
    func clampingResolvesTheSamePayloadWhenTheTrailerIsReal() async throws
    {
        // The mirror image of the case above, with the same arithmetic: here
        // the trailing bytes really are timestamps, and none of them may be
        // handed back as a frame.
        let ticks = ( 0 ..< 384 ).map { Self.startTicks + Int64( $0 ) * 10_000_000 }
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 0
        fields.imageWidth  = 64
        fields.imageHeight = 48
        fields.frameCount  = 1000
        fields.dateTime    = Self.startTicks

        let frames = TestUtilities.indexedFrames( count: 384, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: ticks ).data
        let file  = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount          == 384 )
        #expect( file.hasTimestampTrailer == true )
        #expect( file.timestamps.compactMap { $0 }.count == 384 )
    }

    @Test
    func clampingRecoversTheLayoutAcrossEveryCombination() async throws
    {
        // The header over-declares in every case here, so the layout has to be
        // established from the bytes. Sweeping frame sizes against how many
        // frames and how many timestamps were really written catches a rule
        // that happens to work for one shape and not the rest.
        let geometries: [ ( width: Int32, height: Int32, depth: Int32 ) ] = [ ( 4, 2, 8 ), ( 8, 8, 8 ), ( 64, 48, 8 ), ( 32, 32, 16 ), ( 3, 5, 16 ) ]
        let counts:     [ Int ]                                          = [ 1, 2, 3, 5, 8, 17, 64, 385 ]

        try geometries.forEach
        {
            geometry in

            try counts.forEach
            {
                frames in

                try Set( [ 0, 1, frames / 2, frames - 1, frames ] ).sorted().filter { $0 >= 0 }.forEach
                {
                    stamps in

                    let ticks = ( 0 ..< stamps ).map { Self.startTicks + Int64( $0 ) * 10_000_000 }

                    var fields = TestUtilities.wellFormedHeader

                    fields.imageWidth         = geometry.width
                    fields.imageHeight        = geometry.height
                    fields.pixelDepthPerPlane = geometry.depth
                    fields.frameCount         = 1000
                    fields.dateTime           = Self.startTicks
                    fields.dateTimeUTC        = Self.startTicks

                    let written = TestUtilities.indexedFrames( count: frames, bytesPerFrame: fields.bytesPerFrame )
                    let data    = TestUtilities.File( header: fields, frames: written, timestamps: ticks.isEmpty ? nil : ticks ).data

                    let file    = try SERFile( data: data, options: .lenient )
                    let context = "\( geometry.width )x\( geometry.height )@\( geometry.depth ), \( frames ) frames, \( stamps ) timestamps"

                    #expect( file.frameCount == frames, "\( context ): wrong frame count" )
                    #expect( file.timestamps.compactMap { $0 }.count == min( stamps, frames ), "\( context ): wrong timestamp count" )
                }
            }
        }
    }

    @Test
    func clampingRejectsFrameDataThatRepeatsAPlausibleInstant() async throws
    {
        // A frame whose samples repeat the byte pattern of a believable
        // timestamp reads as that same instant over and over, passing every
        // range test. Real frames are not all captured in one 100 ns tick, so a
        // run that never advances is what gives it away.
        let pattern = TestUtilities.littleEndianBytes( Self.startTicks + 1_000_000 )

        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 8
        fields.imageHeight = 8
        fields.frameCount  = 1000
        fields.dateTime    = Self.startTicks
        fields.dateTimeUTC = Self.startTicks

        let header = fields.data

        let ordinary  = Data( repeating: 0x01, count: 64 )
        let deceptive = Data( ( 0 ..< 8 ).flatMap { _ in pattern } )
        let frames    = Data( ( 0 ..< 11 ).flatMap { _ in ordinary } ) + deceptive
        let file      = try SERFile( data: header + frames, options: .lenient )

        #expect( file.frameCount          == 12 )
        #expect( file.hasTimestampTrailer == false )
    }

    @Test
    func clampingUsesTheLocalStartTimeWhenNoUTCOneIsRecorded() async throws
    {
        // Some files fill in only the local start time. It still bounds where a
        // trailer can begin, once the unknown time zone is allowed for — here
        // the frames sit below the timestamps, so without any bound the walk
        // would carry straight on through them.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount  = 1000
        fields.dateTime    = Self.startTicks
        fields.dateTimeUTC = 0

        let header = fields.data

        let frames  = Data( repeating: 0x02, count: 12 * 8 )
        let trailer = Data( ( 0 ..< 4 ).flatMap { TestUtilities.littleEndianBytes( Self.startTicks + Int64( $0 ) * 10_000_000 ) } )
        let file    = try SERFile( data: header + frames + trailer, options: .lenient )

        #expect( file.frameCount == 12 )
        #expect( file.timestamps.compactMap { $0 }.count == 4 )
    }

    @Test
    func clampsToWholeFramesWhenNoTrailerFits() async throws
    {
        // A payload too small to hold even one frame and its timestamp falls
        // back to counting frames alone, so a truncated capture still exposes
        // what it has. The four trailing bytes leave neither reading exact, so
        // this reaches the fallback rather than an exact-fit rule.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 100
        fields.dateTime   = Self.startTicks

        let frames = TestUtilities.indexedFrames( count: 1, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data + Data( repeating: 0xFF, count: 4 )
        let file = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount          == 1 )
        #expect( file.hasTimestampTrailer == false )
    }

    @Test
    func rejectsAPayloadLengthThatWouldOverflow() async throws
    {
        // A header can legitimately declare a frame size near `Int.max`, at
        // which point multiplying by the frame count wraps. The guard is the
        // only thing standing between that and a trap.
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth         = 3
        fields.imageHeight        = Int32.max
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = Int32.max

        let data = fields.data

        try #require( throws: SERError.self ) { try SERFile( data: data, options: .strict ) }

        #expect( try SERFile( data: data, options: .lenient ).frameCount == 0 )
    }

    @Test
    func acceptsAFileLongerThanItsDeclaredFrames() async throws
    {
        // Extra bytes past the declared frames are not an error: they are where
        // the timestamp trailer lives.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 2

        let frames = TestUtilities.indexedFrames( count: 4, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data
        let file = try SERFile( data: data, options: .strict )

        #expect( file.frameCount == 2 )

        // The surplus frames' pixel bytes sit exactly where a trailer would,
        // and must not be handed back as timestamps.
        #expect( file.timestamps == [ nil, nil ] )
    }

    // MARK: - Frame addressing

    @Test
    func computesTheByteOffsetOfEveryFrame() async throws
    {
        let file = try SERFile( data: TestUtilities.wellFormedHeader( frameCount: 3 ).file.data, options: .strict )

        #expect( try file.byteOffset( ofFrame: 0 ) == 178 )
        #expect( try file.byteOffset( ofFrame: 1 ) == 178 + 8 )
        #expect( try file.byteOffset( ofFrame: 2 ) == 178 + 16 )
    }

    @Test
    func rejectsAnOutOfRangeFrameIndex() async throws
    {
        let file = try SERFile( data: TestUtilities.wellFormedHeader( frameCount: 3 ).file.data, options: .strict )

        try #require( throws: SERError.self ) { try file.byteOffset( ofFrame: -1 ) }
        try #require( throws: SERError.self ) { try file.byteOffset( ofFrame: 3 ) }
        try #require( throws: SERError.self ) { try file.byteOffset( ofFrame: Int.max ) }
    }

    @Test
    func addressesFramesAgainstTheClampedCount() async throws
    {
        // Frames the header declares but the file does not hold must not be
        // addressable.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 4

        let frames = TestUtilities.indexedFrames( count: 2, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data
        let file = try SERFile( data: data, options: .lenient )

        try #require( throws: SERError.self ) { try file.byteOffset( ofFrame: 2 ) }
    }

    @Test
    func returnsTheFrameAtAnIndex() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 1
        fields.frameCount  = 3

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2 ], [ 3, 4 ], [ 5, 6 ] ], timestamps: nil ).data
        let file = try SERFile( data: data, options: .strict )

        #expect( try file.frame( at: 0 ).samples == [ 1, 2 ] )
        #expect( try file.frame( at: 2 ).samples == [ 5, 6 ] )
        #expect( try file.frame( at: 2 ).index   == 2 )
    }

    @Test
    func rejectsAnOutOfRangeFrameRequest() async throws
    {
        let file = try SERFile( data: TestUtilities.wellFormedHeader( frameCount: 3 ).file.data, options: .strict )

        try #require( throws: SERError.self ) { try file.frame( at: -1 ) }
        try #require( throws: SERError.self ) { try file.frame( at: 3 ) }
        try #require( throws: SERError.self ) { try file.frame( at: Int.max ) }
    }

    @Test
    func returnsFramesAgainstTheClampedCount() async throws
    {
        // Frames the header declares but the file does not hold must not be
        // reachable through the frame accessors either.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 4

        let frames = TestUtilities.indexedFrames( count: 2, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data
        let file = try SERFile( data: data, options: .lenient )

        try #require( throws: SERError.self ) { try file.frame( at: 2 ) }
    }

    @Test
    func iteratingTheFileYieldsEveryFrameInOrder() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 1
        fields.frameCount  = 3

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2 ], [ 3, 4 ], [ 5, 6 ] ], timestamps: nil ).data
        let file = try SERFile( data: data, options: .strict )

        #expect( file.map { $0.index }                == [ 0, 1, 2 ] )
        #expect( try file.flatMap { try $0.samples }  == [ 1, 2, 3, 4, 5, 6 ] )
        #expect( file.underestimatedCount             == 3 )
    }

    @Test
    func iteratingAFileWithNoFramesYieldsNothing() async throws
    {
        let file = try SERFile( data: TestUtilities.wellFormedHeader( frameCount: 0 ).file.data, options: .strict )

        #expect( file.map { $0.index }.isEmpty )
    }

    // MARK: - Timestamps

    @Test
    func readsTheTimestampTrailer() async throws
    {
        let ticks = [ Self.startTicks, Self.startTicks + 10_000_000, Self.startTicks + 20_000_000 ]
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 3
        fields.dateTime   = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: ticks ).data
        let file  = try SERFile( data: data, options: .strict )

        #expect( file.hasTimestampTrailer == true )
        #expect( file.timestamps.count    == 3 )

        // Required, not merely expected: subscripting a short array below would
        // trap and take the whole test run down with it.
        let dates = file.timestamps.compactMap { $0 }

        try #require( dates.count == 3 )

        #expect( abs( dates[ 1 ].timeIntervalSince( dates[ 0 ] ) - 1.0 ) < 0.000_001 )
        #expect( abs( dates[ 2 ].timeIntervalSince( dates[ 0 ] ) - 2.0 ) < 0.000_001 )
    }

    @Test
    func reportsNoTrailerWhenTheStartDateIsInvalid() async throws
    {
        // A start date of zero or less means the file carries no trailer.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 2
        fields.dateTime   = 0

        let file = try SERFile( data: TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: nil ).data, options: .strict )

        #expect( file.hasTimestampTrailer == false )
        #expect( file.timestamps          == [ nil, nil ] )
    }

    @Test
    func rejectsAMissingTrailer() async throws
    {
        // The header declares a start date, so a trailer is expected, but none
        // was written.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 2
        fields.dateTime   = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: nil ).data

        try #require( throws: SERError.self ) { try SERFile( data: data, options: .strict ) }

        let file = try SERFile( data: data, options: .lenient )

        #expect( file.hasTimestampTrailer == false )
        #expect( file.timestamps          == [ nil, nil ] )
    }

    @Test
    func rejectsAShortTrailer() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 3
        fields.dateTime   = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ Self.startTicks, Self.startTicks ] ).data

        try #require( throws: SERError.self ) { try SERFile( data: data, options: .strict ) }

        let file = try SERFile( data: data, options: .lenient )

        try #require( file.timestamps.count == 3 )

        #expect( file.timestamps[ 0 ] != nil )
        #expect( file.timestamps[ 1 ] != nil )
        #expect( file.timestamps[ 2 ] == nil )
    }

    @Test
    func routesATruncatedTimestampToTheShortTrailerFlag() async throws
    {
        // Four bytes are not a whole timestamp, but they are still a trailer,
        // so this is a short trailer rather than a missing one.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 1
        fields.dateTime   = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: nil ).data + Data( repeating: 0xFF, count: 4 )

        try #require( throws: SERError.self ) { try SERFile( data: data, options: .strict ) }
        try #require( throws: SERError.self ) { try SERFile( data: data, options: .lenient.subtracting( .allowShortTrailer ) ) }

        let file = try SERFile( data: data, options: .allowShortTrailer )

        #expect( file.timestamps == [ nil ] )

        // Short enough that not one whole timestamp is readable, which is what
        // the flag reports — the tail still counts as a trailer for routing the
        // failure, but not for having any timestamp in it.
        #expect( file.hasTimestampTrailer == false )
    }

    @Test
    func appliesTimestampMaskingToTrailerEntries() async throws
    {
        // The flag governs the trailer's own values, not just the header's
        // start date.
        let raw  = Int64( bitPattern: UInt64( Self.startTicks ) | ( 1 << 63 ) )
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 1
        fields.dateTime   = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ raw ] ).data

        #expect( try SERFile( data: data, options: .strict ).timestamps == [ nil ] )
        #expect( try SERFile( data: data, options: .lenient ).timestamps.first ?? nil != nil )
    }

    @Test
    func acceptsAnEmptySequenceDeclaringAStartDate() async throws
    {
        // No frames means no timestamps are owed, so the absent trailer is not
        // a failure even under strict parsing.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 0
        fields.dateTime   = Self.startTicks

        let file = try SERFile( data: TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: nil ).data, options: .strict )

        #expect( file.frameCount == 0 )
        #expect( file.timestamps.isEmpty )
    }

    @Test
    func trailerFailuresAreGatedByTheirOwnFlags() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 2
        fields.dateTime   = Self.startTicks

        let missing = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: nil ).data

        fields.frameCount = 3

        let short = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ Self.startTicks ] ).data

        try #require( throws: SERError.self ) { try SERFile( data: missing, options: .lenient.subtracting( .allowMissingTrailer ) ) }
        try #require( throws: SERError.self ) { try SERFile( data: short,   options: .lenient.subtracting( .allowShortTrailer ) ) }

        _ = try SERFile( data: missing, options: .allowMissingTrailer )
        _ = try SERFile( data: short,   options: .allowShortTrailer )
    }

    @Test
    func ignoresATrailerLongerThanTheFrameCount() async throws
    {
        // The surplus entries are dropped from the end, so the timestamps kept
        // are the ones belonging to the frames that exist.
        let ticks = ( 0 ..< 5 ).map { Self.startTicks + Int64( $0 ) * 10_000_000 }
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 2
        fields.dateTime   = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: ticks ).data
        let file  = try SERFile( data: data, options: .strict )

        let dates = file.timestamps.compactMap { $0 }

        try #require( file.timestamps.count == 2 )
        try #require( dates.count           == 2 )

        #expect( abs( dates[ 1 ].timeIntervalSince( dates[ 0 ] ) - 1.0 ) < 0.000_001 )
    }

    @Test
    func trailerPresenceFollowsTheStartDateSignNotItsRange() async throws
    {
        // The specification ties the trailer to a positive start date, not to
        // one naming a representable instant. Reading an out-of-range date as
        // "no trailer" would put the trailer's bytes back in reach as frames.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 2
        fields.dateTime   = Int64.max

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ Self.startTicks, Self.startTicks ] ).data
        let file = try SERFile( data: data, options: .strict )

        #expect( file.hasTimestampTrailer == true )
        #expect( file.frameCount          == 2 )
        #expect( file.startTime           == nil )
    }

    @Test
    func exposesTheStartTimes() async throws
    {
        // The local field is a wall-clock reading with no zone attached, so it
        // is expressed as though it were UTC; only the UTC field names the true
        // instant.
        let utc  = Self.startTicks - ( 2 * 3600 * 10_000_000 )
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount  = 1
        fields.dateTime    = Self.startTicks
        fields.dateTimeUTC = utc

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ Self.startTicks ] ).data
        let file = try SERFile( data: data, options: .strict )

        let start   = try #require( file.startTime )
        let instant = try #require( file.startTimeUTC )

        #expect( abs( start.timeIntervalSince( instant ) - 7200 ) < 0.000_001 )
    }

    @Test
    func exposesTheUTCOffset() async throws
    {
        // A capture machine two hours ahead of UTC gives a positive offset, and
        // adding it back to the instant reproduces the local reading.
        let utc  = Self.startTicks - ( 2 * 3600 * 10_000_000 )
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount  = 1
        fields.dateTime    = Self.startTicks
        fields.dateTimeUTC = utc

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ Self.startTicks ] ).data
        let file = try SERFile( data: data, options: .strict )

        let offset  = try #require( file.utcOffset )
        let start   = try #require( file.startTime )
        let instant = try #require( file.startTimeUTC )

        #expect( abs( offset - 7200 ) < 0.000_001 )
        #expect( abs( instant.addingTimeInterval( offset ).timeIntervalSince( start ) ) < 0.000_001 )
    }

    @Test
    func hasNoUTCOffsetWithoutBothStartTimes() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount  = 1
        fields.dateTime    = 0
        fields.dateTimeUTC = Self.startTicks

        let noLocal = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: nil ).data

        fields.dateTime    = Self.startTicks
        fields.dateTimeUTC = 0

        let noUTC = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ Self.startTicks ] ).data

        #expect( try SERFile( data: noLocal, options: .strict ).utcOffset == nil )
        #expect( try SERFile( data: noUTC,   options: .strict ).utcOffset == nil )
    }

    @Test
    func honorsTimestampMaskingWhenDecidingTrailerPresence() async throws
    {
        // A start date whose two undocumented high bits are set reads as
        // invalid until masking is allowed, at which point the file does
        // declare a trailer after all.
        let raw   = Int64( bitPattern: UInt64( Self.startTicks ) | ( 1 << 63 ) )
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 1
        fields.dateTime   = raw

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ Self.startTicks ] ).data

        let strict  = try SERFile( data: data, options: .strict )
        let lenient = try SERFile( data: data, options: .lenient )

        #expect( strict.hasTimestampTrailer  == false )
        #expect( lenient.hasTimestampTrailer == true )

        try #require( lenient.timestamps.count == 1 )

        #expect( lenient.timestamps[ 0 ] != nil )
    }

    @Test
    func timestampsAreParsedOnceAndCached() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 2
        fields.dateTime   = Self.startTicks

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ Self.startTicks, Self.startTicks ] ).data
        let file = try SERFile( data: data, options: .strict )

        #expect( file.cachedTimestamps == nil )

        let first = file.timestamps

        #expect( file.cachedTimestamps != nil )
        #expect( file.timestamps == first )
    }

    // MARK: - Description

    @Test
    func descriptionSummarizesTheFile() async throws
    {
        // The two start times are rendered from different fields, so they are
        // given different values here: a description reading the same field
        // twice would otherwise go unnoticed.
        let utc  = Self.startTicks - ( 2 * 3600 * 10_000_000 )
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount  = 3
        fields.dateTime    = Self.startTicks
        fields.dateTimeUTC = utc

        let data = TestUtilities.File( header: fields, frames: fields.indexedFrames, timestamps: [ Self.startTicks, Self.startTicks, Self.startTicks ] ).data
        let file = try SERFile( data: data, options: .strict )

        let description  = file.description
        let start        = try #require( file.startTime )
        let startUTC     = try #require( file.startTimeUTC )

        #expect( description.contains( "SERFile" ) )
        #expect( description.contains( "Frame Count:       3" ) )
        #expect( description.contains( "Declared Frames:   3" ) )
        #expect( description.contains( "Bytes Per Frame:   8" ) )
        #expect( description.contains( "Timestamp Trailer: Yes" ) )
        #expect( description.contains( "Start Time:        \( start )" ) )
        #expect( description.contains( "Start Time UTC:    \( startUTC )" ) )
    }

    // MARK: - Debayering

    /// The error a stub implementation throws, so a propagated one can be told
    /// apart from anything SwiftSER raises itself.
    struct DelegateError: Error
    {}

    /// A ``SERDebayering`` a test can steer, and afterwards ask what it was
    /// given.
    ///
    /// A class rather than a struct, since the protocol's requirements are
    /// non-mutating and a test needs the record of the calls the file made.
    final class Delegate: SERDebayering
    {
        /// Whether ``supports(pattern:)`` claims the pattern it is asked about.
        let accepts: Bool

        /// What ``debayer(mosaic:width:height:pattern:)`` returns, or `nil` for
        /// it to throw ``DelegateError`` instead.
        let output: ( ( Int, Int ) -> [ Double ] )?

        /// The patterns ``supports(pattern:)`` was asked about.
        private( set ) var asked: [ SERBayerPattern ] = []

        /// What ``debayer(mosaic:width:height:pattern:)`` was called with.
        private( set ) var calls: [ ( mosaic: [ Double ], width: Int, height: Int, pattern: SERBayerPattern ) ] = []

        /// Creates a stub implementation.
        ///
        /// - Parameters:
        ///   - accepts: Whether it claims the patterns it is asked about.
        ///   - output:  What it returns for a pattern it claims, given the
        ///              image's width and height, or `nil` for it to throw.
        init( accepts: Bool, output: ( ( Int, Int ) -> [ Double ] )? )
        {
            self.accepts = accepts
            self.output  = output
        }

        /// Whether this implementation claims the pattern, recording the
        /// question.
        ///
        /// - Parameter pattern: The mosaic laid over the sensor.
        /// - Returns: What the stub was created with.
        func supports( pattern: SERBayerPattern ) -> Bool
        {
            self.asked.append( pattern )

            return self.accepts
        }

        /// Returns what the stub was created with, recording the call.
        ///
        /// - Parameters:
        ///   - mosaic:  The frame's samples.
        ///   - width:   The image's width, in pixels.
        ///   - height:  The image's height, in pixels.
        ///   - pattern: The mosaic laid over the sensor.
        /// - Returns: What the stub was created with.
        /// - Throws: ``DelegateError`` when the stub was created with no output.
        func debayer( mosaic: [ Double ], width: Int, height: Int, pattern: SERBayerPattern ) throws -> [ Double ]
        {
            self.calls.append( ( mosaic, width, height, pattern ) )

            guard let output = self.output
            else
            {
                throw DelegateError()
            }

            return output( width, height )
        }
    }

    /// Every color ID carrying a mosaic, with the pattern it names.
    static let bayerColorIDs: [ ( colorID: Int32, pattern: SERBayerPattern ) ] = [
        (  8, .rggb ),
        (  9, .grbg ),
        ( 10, .gbrg ),
        ( 11, .bggr ),
        ( 16, .cyym ),
        ( 17, .ycmy ),
        ( 18, .ymcy ),
        ( 19, .myyc ),
    ]

    /// Every color ID that is not a mosaic, with the number of planes it holds.
    static let plainColorIDs: [ ( colorID: Int32, planes: Int ) ] = [
        (   0, 1 ),
        ( 100, 3 ),
        ( 101, 3 ),
    ]

    /// A one-frame 4×4 8-bit file of the given color ID, whose bytes count from
    /// one.
    ///
    /// A single-plane file therefore holds the mosaic `1 ... 16`, which is what
    /// the built-in implementation's own tests are written against.
    ///
    /// - Parameter colorID: The raw color ID the header declares.
    /// - Returns: The parsed file.
    /// - Throws: Any error raised while parsing.
    static func fileDeclaring( colorID: Int32 ) throws -> SERFile
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = colorID
        fields.imageWidth  = 4
        fields.imageHeight = 4
        fields.frameCount  = 1

        let frame = ( 0 ..< fields.bytesPerFrame ).map { UInt8( truncatingIfNeeded: $0 + 1 ) }

        return try SERFile( data: TestUtilities.File( header: fields, frames: [ frame ], timestamps: nil ).data, options: .strict )
    }

    @Test
    func everyColorIDTableIsListed() async throws
    {
        // The tests below iterate these tables, so a row dropped from one would
        // leave them passing while proving less. Together they are every color
        // ID the specification defines.
        #expect( Self.bayerColorIDs.map { $0.colorID } == [ 8, 9, 10, 11, 16, 17, 18, 19 ] )
        #expect( Self.plainColorIDs.map { $0.colorID } == [ 0, 100, 101 ] )
    }

    // MARK: - Debayering defaults

    @Test
    func aFileDebayersWithTheBuiltInImplementationByDefault() async throws
    {
        let file = try Self.fileDeclaring( colorID: 8 )

        #expect( file.debayering            == nil )
        #expect( file.debayerFailurePolicy  == .fallBackToBuiltIn )
        #expect( try file.debayeredSamples( ofFrame: 0 ) == Test_SERBilinearDebayering.fourByFourRGGB )
    }

    @Test
    func everyMosaicColorIDReachesTheDebayerer() async throws
    {
        try Self.bayerColorIDs.forEach
        {
            let delegate = Delegate( accepts: false, output: nil )
            let file     = try Self.fileDeclaring( colorID: $0.colorID )

            file.debayering = delegate

            let rgb = try file.debayeredSamples( ofFrame: 0 )

            #expect( delegate.asked == [ $0.pattern ], "color ID \( $0.colorID ) asks about the wrong pattern" )
            #expect( rgb.count      == 4 * 4 * 3,      "color ID \( $0.colorID ) produces the wrong sample count" )
        }
    }

    // MARK: - Frames that carry no mosaic

    @Test
    func aFrameThatIsNotAMosaicComesBackUnchanged() async throws
    {
        try Self.plainColorIDs.forEach
        {
            let delegate = Delegate( accepts: true, output: { _, _ in [] } )
            let file     = try Self.fileDeclaring( colorID: $0.colorID )

            file.debayering = delegate

            let samples = try file.debayeredSamples( ofFrame: 0 )

            #expect( samples          == ( try file.frame( at: 0 ).samples ), "color ID \( $0.colorID ) alters its samples" )
            #expect( samples.count    == 4 * 4 * $0.planes,                   "color ID \( $0.colorID ) changes its plane count" )
            #expect( delegate.asked.isEmpty,                                  "color ID \( $0.colorID ) consults the debayering" )
            #expect( delegate.calls.isEmpty,                                  "color ID \( $0.colorID ) is debayered" )
        }
    }

    @Test
    func rejectsADebayerRequestForAnOutOfRangeFrame() async throws
    {
        let file = try Self.fileDeclaring( colorID: 8 )

        #expect( throws: SERError.self )
        {
            try file.debayeredSamples( ofFrame: 1 )
        }

        #expect( throws: SERError.self )
        {
            try file.debayeredSamples( ofFrame: -1 )
        }
    }

    // MARK: - Debayering delegation

    @Test
    func aDelegateThatClaimsThePatternIsUsed() async throws
    {
        let marker   = [ Double ]( repeating: 42, count: 4 * 4 * 3 )
        let delegate = Delegate( accepts: true, output: { _, _ in marker } )
        let file     = try Self.fileDeclaring( colorID: 8 )

        file.debayering = delegate

        #expect( try file.debayeredSamples( ofFrame: 0 ) == marker )
        #expect( delegate.calls.count                    == 1 )
    }

    @Test
    func aDelegateIsHandedTheFramesSamplesAndGeometry() async throws
    {
        let delegate = Delegate( accepts: true, output: { width, height in [ Double ]( repeating: 0, count: width * height * 3 ) } )
        let file     = try Self.fileDeclaring( colorID: 9 )

        file.debayering = delegate

        _ = try file.debayeredSamples( ofFrame: 0 )

        let call = try #require( delegate.calls.first )

        #expect( call.mosaic  == ( try file.frame( at: 0 ).samples ) )
        #expect( call.width   == 4 )
        #expect( call.height  == 4 )
        #expect( call.pattern == .grbg )
    }

    @Test
    func aDelegateThatDeclinesFallsBackWhateverThePolicy() async throws
    {
        // Declining is part of the protocol, not a failure, so the policy has
        // no say in it.
        try Test_SERDebayerFailurePolicy.policies.forEach
        {
            let delegate = Delegate( accepts: false, output: { _, _ in [] } )
            let file     = try Self.fileDeclaring( colorID: 8 )

            file.debayering           = delegate
            file.debayerFailurePolicy = $0.policy

            #expect( try file.debayeredSamples( ofFrame: 0 ) == Test_SERBilinearDebayering.fourByFourRGGB, "\( $0.policy ) does not fall back" )
            #expect( delegate.asked                          == [ .rggb ] )
            #expect( delegate.calls.isEmpty,                  "\( $0.policy ) debayers through an implementation that declined" )
        }
    }

    @Test
    func aDelegateThatThrowsFallsBackUnderTheDefaultPolicy() async throws
    {
        let delegate = Delegate( accepts: true, output: nil )
        let file     = try Self.fileDeclaring( colorID: 8 )

        file.debayering = delegate

        #expect( try file.debayeredSamples( ofFrame: 0 ) == Test_SERBilinearDebayering.fourByFourRGGB )
        #expect( delegate.calls.count                    == 1 )
    }

    @Test
    func aDelegateThatThrowsIsReportedUnderThePropagatePolicy() async throws
    {
        let delegate = Delegate( accepts: true, output: nil )
        let file     = try Self.fileDeclaring( colorID: 8 )

        file.debayering           = delegate
        file.debayerFailurePolicy = .propagate

        // The delegate's own error, not one SwiftSER substituted for it.
        #expect( throws: DelegateError.self )
        {
            try file.debayeredSamples( ofFrame: 0 )
        }
    }

    @Test
    func aDelegateReturningTheWrongSampleCountIsAFailure() async throws
    {
        // A result of the wrong length cannot be interpreted as an image, so it
        // is a failure like any other and answers to the same policy.
        let file = try Self.fileDeclaring( colorID: 8 )

        file.debayering = Delegate( accepts: true, output: { width, height in [ Double ]( repeating: 0, count: width * height ) } )

        #expect( try file.debayeredSamples( ofFrame: 0 ) == Test_SERBilinearDebayering.fourByFourRGGB )

        file.debayerFailurePolicy = .propagate

        #expect( throws: SERError.self )
        {
            try file.debayeredSamples( ofFrame: 0 )
        }
    }

    @Test
    func aDelegateIsConsultedOnceForEveryFrameItDebayers() async throws
    {
        // The properties are read at the moment a frame is debayered, so a
        // delegate installed after a file is opened still takes over, and one
        // removed again gives the work back.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 8
        fields.imageWidth  = 4
        fields.imageHeight = 4
        fields.frameCount  = 2

        let frames   = [ ( 0 ..< 16 ).map { UInt8( $0 + 1 ) }, ( 0 ..< 16 ).map { UInt8( $0 + 17 ) } ]
        let file     = try SERFile( data: TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data, options: .strict )
        let marker   = [ Double ]( repeating: 7, count: 4 * 4 * 3 )
        let delegate = Delegate( accepts: true, output: { _, _ in marker } )

        #expect( try file.debayeredSamples( ofFrame: 0 ) == Test_SERBilinearDebayering.fourByFourRGGB )

        file.debayering = delegate

        #expect( try file.debayeredSamples( ofFrame: 0 ) == marker )
        #expect( try file.debayeredSamples( ofFrame: 1 ) == marker )

        file.debayering = nil

        #expect( try file.debayeredSamples( ofFrame: 0 ) == Test_SERBilinearDebayering.fourByFourRGGB )
        #expect( delegate.calls.count                    == 2 )
    }

    @Test
    func debayersASixteenBitMosaic() async throws
    {
        // The mosaic reaches the debayering as `samples` decodes it, so a 16-bit
        // capture arrives as the values it stores rather than as its bytes.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 8
        fields.imageWidth         = 2
        fields.imageHeight        = 2
        fields.pixelDepthPerPlane = 16
        fields.littleEndian       = 1
        fields.frameCount         = 1

        let frame = [ UInt8 ]( [ 0x00, 0x80, 0xFF, 0xFF, 0x01, 0x00, 0x02, 0x00 ] )
        let file  = try SERFile( data: TestUtilities.File( header: fields, frames: [ frame ], timestamps: nil ).data, options: .strict )

        // The mosaic is 32768, 65535 / 1, 2 — red at the first site, blue at the
        // last, green at the other two, whose average is 32768. Red and blue
        // are sampled once each, so they spread over the whole tile.
        let rgb = try file.debayeredSamples( ofFrame: 0 )

        #expect( rgb == [
            32768, 32768, 2,
            32768, 65535, 2,
            32768,     1, 2,
            32768, 32768, 2,
        ] )
    }
}
