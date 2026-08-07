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
        let file = try SERFile( data: TestUtilities.fileData( frameCount: 3 ), options: .strict )

        #expect( file.header.imageWidth  == 4 )
        #expect( file.header.imageHeight == 2 )
        #expect( file.frameCount         == 3 )
    }

    @Test
    func rejectsDataTooShortForAHeader() async throws
    {
        try #require( throws: SERError.self ) { try SERFile( data: Data(), options: .lenient ) }
        try #require( throws: SERError.self ) { try SERFile( data: TestUtilities.headerData().prefix( 100 ), options: .lenient ) }
    }

    @Test
    func acceptsAnEmptySequence() async throws
    {
        // A header declaring no frames is degenerate but well-formed.
        let file = try SERFile( data: TestUtilities.fileData( frameCount: 0 ), options: .strict )

        #expect( file.frameCount == 0 )
        #expect( file.timestamps.isEmpty )
    }

    @Test
    func readsFromAFileURL() async throws
    {
        let url  = try TestUtilities.temporaryFile( containing: TestUtilities.fileData( frameCount: 2 ), named: "capture.ser" )
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
        let data = TestUtilities.fileData( frameCount: 4, framesPresent: 2 )

        try #require( throws: SERError.self ) { try SERFile( data: data, options: .strict ) }
    }

    @Test
    func clampsTheFrameCountToWhatThePayloadHolds() async throws
    {
        let data = TestUtilities.fileData( frameCount: 4, framesPresent: 2 )
        let file = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount        == 2 )
        #expect( file.header.frameCount == 4 )
    }

    @Test
    func clampingIsGatedByItsOwnFlag() async throws
    {
        let data    = TestUtilities.fileData( frameCount: 4, framesPresent: 2 )
        let options = SERParsingOptions.lenient.subtracting( .allowFrameCountMismatch )

        try #require( throws: SERError.self ) { try SERFile( data: data, options: options ) }

        #expect( try SERFile( data: data, options: .allowFrameCountMismatch ).frameCount == 2 )
    }

    @Test
    func clampsAPartialTrailingFrame() async throws
    {
        // A capture cut mid-frame yields whole frames only, never a fragment.
        let data = TestUtilities.fileData( frameCount: 4, framesPresent: 2 ) + Data( repeating: 0xFF, count: 3 )
        let file = try SERFile( data: data, options: .lenient )

        #expect( file.frameCount == 2 )
    }

    @Test
    func clampingNeverAddressesTrailerBytesAsFrames() async throws
    {
        // The header over-declares, and the file carries a trailer. Dividing the
        // remaining bytes by the frame size alone would count the trailer's
        // bytes as frames and hand back a frame overlapping it.
        let data = TestUtilities.fileData(
            frameCount:    100,
            dateTime:      Self.startTicks,
            framesPresent: 2,
            timestamps:    [ Self.startTicks, Self.startTicks + 10_000_000 ]
        )

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
        let data = TestUtilities.fileData( colorID: 0, imageWidth: 64, imageHeight: 48, frameCount: 1000, dateTime: Self.startTicks, framesPresent: 10 )
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
        let data = TestUtilities.fileData( frameCount: 100, dateTime: Self.startTicks, framesPresent: 2, timestamps: [ Self.startTicks ] )
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
        let data = TestUtilities.fileData( colorID: 0, imageWidth: 64, imageHeight: 48, frameCount: 1000, dateTime: Self.startTicks, framesPresent: 385 )
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
        let data  = TestUtilities.fileData( colorID: 0, imageWidth: 64, imageHeight: 48, frameCount: 1000, dateTime: Self.startTicks, framesPresent: 384, timestamps: ticks )
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

                    let data = TestUtilities.fileData(
                        imageWidth:         geometry.width,
                        imageHeight:        geometry.height,
                        pixelDepthPerPlane: geometry.depth,
                        frameCount:         1000,
                        dateTime:           Self.startTicks,
                        dateTimeUTC:        Self.startTicks,
                        framesPresent:      frames,
                        timestamps:         ticks.isEmpty ? nil : ticks
                    )

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

        let header = TestUtilities.headerData(
            imageWidth:  8,
            imageHeight: 8,
            frameCount:  1000,
            dateTime:    Self.startTicks,
            dateTimeUTC: Self.startTicks
        )

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
        let header = TestUtilities.headerData(
            frameCount:  1000,
            dateTime:    Self.startTicks,
            dateTimeUTC: 0
        )

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
        let data = TestUtilities.fileData( frameCount: 100, dateTime: Self.startTicks, framesPresent: 1 ) + Data( repeating: 0xFF, count: 4 )
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
        let data = TestUtilities.headerData( imageWidth: 3, imageHeight: Int32.max, pixelDepthPerPlane: 8, frameCount: Int32.max )

        try #require( throws: SERError.self ) { try SERFile( data: data, options: .strict ) }

        #expect( try SERFile( data: data, options: .lenient ).frameCount == 0 )
    }

    @Test
    func acceptsAFileLongerThanItsDeclaredFrames() async throws
    {
        // Extra bytes past the declared frames are not an error: they are where
        // the timestamp trailer lives.
        let data = TestUtilities.fileData( frameCount: 2, framesPresent: 4 )
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
        let file = try SERFile( data: TestUtilities.fileData( frameCount: 3 ), options: .strict )

        #expect( try file.byteOffset( ofFrame: 0 ) == 178 )
        #expect( try file.byteOffset( ofFrame: 1 ) == 178 + 8 )
        #expect( try file.byteOffset( ofFrame: 2 ) == 178 + 16 )
    }

    @Test
    func rejectsAnOutOfRangeFrameIndex() async throws
    {
        let file = try SERFile( data: TestUtilities.fileData( frameCount: 3 ), options: .strict )

        try #require( throws: SERError.self ) { try file.byteOffset( ofFrame: -1 ) }
        try #require( throws: SERError.self ) { try file.byteOffset( ofFrame: 3 ) }
        try #require( throws: SERError.self ) { try file.byteOffset( ofFrame: Int.max ) }
    }

    @Test
    func addressesFramesAgainstTheClampedCount() async throws
    {
        // Frames the header declares but the file does not hold must not be
        // addressable.
        let data = TestUtilities.fileData( frameCount: 4, framesPresent: 2 )
        let file = try SERFile( data: data, options: .lenient )

        try #require( throws: SERError.self ) { try file.byteOffset( ofFrame: 2 ) }
    }

    // MARK: - Timestamps

    @Test
    func readsTheTimestampTrailer() async throws
    {
        let ticks = [ Self.startTicks, Self.startTicks + 10_000_000, Self.startTicks + 20_000_000 ]
        let data  = TestUtilities.fileData( frameCount: 3, dateTime: Self.startTicks, timestamps: ticks )
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
        let file = try SERFile( data: TestUtilities.fileData( frameCount: 2, dateTime: 0 ), options: .strict )

        #expect( file.hasTimestampTrailer == false )
        #expect( file.timestamps          == [ nil, nil ] )
    }

    @Test
    func rejectsAMissingTrailer() async throws
    {
        // The header declares a start date, so a trailer is expected, but none
        // was written.
        let data = TestUtilities.fileData( frameCount: 2, dateTime: Self.startTicks )

        try #require( throws: SERError.self ) { try SERFile( data: data, options: .strict ) }

        let file = try SERFile( data: data, options: .lenient )

        #expect( file.hasTimestampTrailer == false )
        #expect( file.timestamps          == [ nil, nil ] )
    }

    @Test
    func rejectsAShortTrailer() async throws
    {
        let data = TestUtilities.fileData( frameCount: 3, dateTime: Self.startTicks, timestamps: [ Self.startTicks, Self.startTicks ] )

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
        let data = TestUtilities.fileData( frameCount: 1, dateTime: Self.startTicks ) + Data( repeating: 0xFF, count: 4 )

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
        let data = TestUtilities.fileData( frameCount: 1, dateTime: Self.startTicks, timestamps: [ raw ] )

        #expect( try SERFile( data: data, options: .strict ).timestamps == [ nil ] )
        #expect( try SERFile( data: data, options: .lenient ).timestamps.first ?? nil != nil )
    }

    @Test
    func acceptsAnEmptySequenceDeclaringAStartDate() async throws
    {
        // No frames means no timestamps are owed, so the absent trailer is not
        // a failure even under strict parsing.
        let file = try SERFile( data: TestUtilities.fileData( frameCount: 0, dateTime: Self.startTicks ), options: .strict )

        #expect( file.frameCount == 0 )
        #expect( file.timestamps.isEmpty )
    }

    @Test
    func trailerFailuresAreGatedByTheirOwnFlags() async throws
    {
        let missing = TestUtilities.fileData( frameCount: 2, dateTime: Self.startTicks )
        let short   = TestUtilities.fileData( frameCount: 3, dateTime: Self.startTicks, timestamps: [ Self.startTicks ] )

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
        let data  = TestUtilities.fileData( frameCount: 2, dateTime: Self.startTicks, timestamps: ticks )
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
        let data = TestUtilities.fileData( frameCount: 2, dateTime: Int64.max, timestamps: [ Self.startTicks, Self.startTicks ] )
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
        let data = TestUtilities.fileData( frameCount: 1, dateTime: Self.startTicks, dateTimeUTC: utc, timestamps: [ Self.startTicks ] )
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
        let data = TestUtilities.fileData( frameCount: 1, dateTime: Self.startTicks, dateTimeUTC: utc, timestamps: [ Self.startTicks ] )
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
        let noLocal = TestUtilities.fileData( frameCount: 1, dateTime: 0, dateTimeUTC: Self.startTicks )
        let noUTC   = TestUtilities.fileData( frameCount: 1, dateTime: Self.startTicks, dateTimeUTC: 0, timestamps: [ Self.startTicks ] )

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
        let data  = TestUtilities.fileData( frameCount: 1, dateTime: raw, timestamps: [ Self.startTicks ] )

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
        let data = TestUtilities.fileData( frameCount: 2, dateTime: Self.startTicks, timestamps: [ Self.startTicks, Self.startTicks ] )
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
        let data = TestUtilities.fileData( frameCount: 3, dateTime: Self.startTicks, dateTimeUTC: utc, timestamps: [ Self.startTicks, Self.startTicks, Self.startTicks ] )
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
}
