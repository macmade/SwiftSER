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

#if canImport( AVFoundation )

import AVFoundation
import Foundation
@testable import SwiftSER
import Testing

/// Run one at a time.
///
/// Every test here encodes a movie and reads it back, and the platform allows
/// only so many codec sessions at once: run in parallel, several of these block
/// inside `copyNextSampleBuffer` waiting for a session that never comes free,
/// and the whole test process stalls — including the suites that have nothing
/// to do with movies. Confirmed by sampling the stalled process, which showed
/// five of these tests stopped in exactly that call.
@Suite( .serialized )
struct Test_SERMovieWriter
{
    /// The progress fractions an export reported, gathered from its callback.
    ///
    /// A locked box rather than a captured array: the callback is `@Sendable`,
    /// so it cannot close over a `var` in the test's own scope.
    final class Reported: @unchecked Sendable
    {
        /// Guards ``storage`` against the callback being invoked from anywhere.
        private let lock = NSLock()

        /// The fractions reported so far.
        private var storage: [ Double ] = []

        /// Records one reported fraction.
        ///
        /// - Parameter value: The fraction the export reported.
        func append( _ value: Double )
        {
            self.lock.lock()

            defer
            {
                self.lock.unlock()
            }

            self.storage.append( value )
        }

        /// Everything reported so far, in the order it arrived.
        var values: [ Double ]
        {
            self.lock.lock()

            defer
            {
                self.lock.unlock()
            }

            return self.storage
        }
    }

    /// Somewhere to put a task a callback of its own has to reach.
    ///
    /// An export that cancels itself part way through needs its own handle, and
    /// the handle only exists once the task has been made.
    final class TaskBox: @unchecked Sendable
    {
        /// Guards ``storage`` against the callback reading it while the test
        /// writes it.
        private let lock = NSLock()

        /// The running export.
        private var storage: Task< Void, Error >?

        /// The running export, or `nil` before it has been made.
        var task: Task< Void, Error >?
        {
            get
            {
                self.lock.lock()

                defer
                {
                    self.lock.unlock()
                }

                return self.storage
            }

            set
            {
                self.lock.lock()

                defer
                {
                    self.lock.unlock()
                }

                self.storage = newValue
            }
        }
    }

    /// A tick value naming a valid instant, used as the capture's start.
    static let startTicks = Int64( 635_000_000_000_000_000 )

    /// The number of 100 ns ticks in one second.
    static let ticksPerSecond = Int64( 10_000_000 )

    /// Every codec, with whether it preserves an odd frame size.
    ///
    /// H.264 and HEVC encode in macroblocks and round an odd dimension *down*
    /// to the next even one, which a 5×3 capture exported through either comes
    /// back from as 4×2. ProRes carries the odd size through untouched. This is
    /// the encoder's behavior, not the writer's, and it is pinned here so that
    /// the documentation saying so cannot quietly stop being true.
    static let codecs: [ ( codec: SERMovieCodec, keepsOddSize: Bool ) ] = [
        ( .h264,       false ),
        ( .hevc,       false ),
        ( .proRes422,  true  ),
        ( .proRes4444, true  ),
    ]

    @Test
    func everyMovieTableIsListed() async throws
    {
        // The tests below iterate this table, so a row dropped from it would
        // leave them passing while proving less.
        #expect( Self.codecs.map { $0.codec }        == SERMovieCodec.allCases )
        #expect( Self.codecs.map { $0.keepsOddSize } == [ false, false, true, true ] )
    }

    // MARK: - A complete export

    @Test
    func exportsAMonoSequenceToAPlayableMovie() async throws
    {
        let file  = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 3, timestamps: nil )
        let url   = try TestUtilities.temporaryURL( named: "mono.mov" )
        let movie = try await Self.export( file: file, to: url, codec: .h264, frameRate: .constant( 10 ) )

        #expect( movie.width    == 16 )
        #expect( movie.height   == 16 )
        #expect( movie.frames   == 3 )
        #expect( abs( movie.duration - 0.3 ) < 0.001 )
    }

    @Test
    func exportsAMosaicSequenceInColor() async throws
    {
        // A mosaic goes through the file's debayering on the way out, so the
        // movie is color even though the frames are one plane.
        let file  = try Self.monoFile( colorID: 8, width: 16, height: 16, frames: 2, timestamps: nil )
        let url   = try TestUtilities.temporaryURL( named: "mosaic.mov" )
        let movie = try await Self.export( file: file, to: url, codec: .h264, frameRate: .constant( 10 ) )

        #expect( movie.width  == 16 )
        #expect( movie.height == 16 )
        #expect( movie.frames == 2 )
    }

    @Test
    func exportsThroughEveryCodec() async throws
    {
        try await TestUtilities.asyncForEach( Self.codecs )
        {
            entry in

            let file  = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 2, timestamps: nil )
            let url   = try TestUtilities.temporaryURL( named: "codec.mov" )
            let movie = try await Self.export( file: file, to: url, codec: entry.codec, frameRate: .constant( 10 ) )

            #expect( movie.frames == 2,  "\( entry.codec ) writes the wrong number of frames" )
            #expect( movie.width  == 16, "\( entry.codec ) writes the wrong width" )
        }
    }

    @Test
    func anOddFrameSizeSurvivesOnlyTheCodecsThatAllowIt() async throws
    {
        try await TestUtilities.asyncForEach( Self.codecs )
        {
            entry in

            let file  = try Self.monoFile( colorID: 0, width: 5, height: 3, frames: 2, timestamps: nil )
            let url   = try TestUtilities.temporaryURL( named: "odd.mov" )
            let movie = try await Self.export( file: file, to: url, codec: entry.codec, frameRate: .constant( 10 ) )

            #expect( movie.width  == ( entry.keepsOddSize ? 5 : 4 ), "\( entry.codec ) rounds the width unexpectedly" )
            #expect( movie.height == ( entry.keepsOddSize ? 3 : 2 ), "\( entry.codec ) rounds the height unexpectedly" )
        }
    }

    @Test
    func refusesAOnePixelDimensionThroughAMacroblockCodec() async throws
    {
        // Rounding an odd dimension down takes 1 to nothing, and the encoder
        // does not complain: without the guard the export reports success and
        // writes a movie no reader will open, which is worse than failing.
        // ProRes rounds nothing and takes the same geometry happily.
        try await TestUtilities.asyncForEach( Self.codecs )
        {
            entry in

            let file = try Self.monoFile( colorID: 0, width: 1, height: 3, frames: 2, timestamps: nil )
            let url  = try TestUtilities.temporaryURL( named: "sliver.mov" )

            guard entry.keepsOddSize
            else
            {
                let writer = SERMovieWriter( options: SERMovieExportOptions( codec: entry.codec, frameRate: .constant( 10 ), scaled: true ) )

                await Self.expectMovieExportFailure( containing: "rounds a dimension of 1 down" )
                {
                    try await writer.write( file: file, to: url, progress: nil )
                }

                return
            }

            let movie = try await Self.export( file: file, to: url, codec: entry.codec, frameRate: .constant( 10 ) )

            #expect( movie.width  == 1, "\( entry.codec ) does not keep a one-pixel width" )
            #expect( movie.height == 3 )
        }
    }

    @Test
    func writesEachFrameTheRightWayUp() async throws
    {
        // A vertical flip would pass every other test here: the dimensions, the
        // frame count and the duration would all still be right. Core Graphics
        // puts its origin at the bottom left and a pixel buffer's first row is
        // its top, so the two have to be reconciled somewhere.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 0
        fields.imageWidth  = 16
        fields.imageHeight = 16
        fields.frameCount  = 1

        // A white top row over a black frame.
        let frame  = ( 0 ..< fields.bytesPerFrame ).map { UInt8( $0 < 16 ? 255 : 0 ) }
        let file   = try SERFile( data: TestUtilities.File( header: fields, frames: [ frame ], timestamps: nil ).data, options: .strict )
        let url    = try TestUtilities.temporaryURL( named: "orientation.mov" )

        // ProRes 4444 rather than H.264, so what comes back is what went in
        // rather than what a lossy encoder made of it.
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .proRes4444, frameRate: .constant( 10 ), scaled: true ) )

        try await writer.write( file: file, to: url, progress: nil )

        let rows = try await Self.firstAndLastRow( at: url )

        #expect( rows.first > 200, "the frame's top row is not the movie's top row" )
        #expect( rows.last  < 50,  "the frame's bottom row is not the movie's bottom row" )
    }

    @Test
    func writesEveryFrameInOrderAndNotTheFirstOne() async throws
    {
        // The milestone's whole point, and the one thing every other test here
        // is blind to: exporting frame 0 over and over would still give the
        // right dimensions, the right count and the right duration. The frames
        // are well separated in brightness so a decoder cannot blur one into
        // the next, and written through ProRes 4444 so what comes back is what
        // went out.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 0
        fields.imageWidth  = 16
        fields.imageHeight = 16
        fields.frameCount  = 5

        let levels = [ UInt8( 20 ), 60, 100, 140, 180 ]
        let frames = levels.map { [ UInt8 ]( repeating: $0, count: fields.bytesPerFrame ) }
        let file   = try SERFile( data: TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data, options: .strict )
        let url    = try TestUtilities.temporaryURL( named: "ordered.mov" )
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .proRes4444, frameRate: .constant( 10 ), scaled: true ) )

        try await writer.write( file: file, to: url, progress: nil )

        let decoded = try await Self.frameLevels( at: url )

        #expect( decoded.count == levels.count )

        // Compared with a tolerance, since the pixels travel through a color
        // conversion on the way in and out; the point is that each movie frame
        // carries its own SER frame, in order.
        try decoded.enumerated().forEach
        {
            let expected = Int( try #require( levels.indices.contains( $0.offset ) ? levels[ $0.offset ] : nil ) )

            #expect( abs( Int( $0.element ) - expected ) < 10, "movie frame \( $0.offset ) holds \( $0.element ), not \( expected )" )
        }
    }

    // MARK: - Frame rate

    @Test
    func derivesTheFrameRateFromTheTrailerTimestamps() async throws
    {
        // Three frames half a second apart is two frames a second, so three of
        // them run for a second and a half.
        let ticks = [ Self.startTicks, Self.startTicks + Self.ticksPerSecond / 2, Self.startTicks + Self.ticksPerSecond ]
        let file  = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 3, timestamps: ticks )
        let url   = try TestUtilities.temporaryURL( named: "timestamped.mov" )
        let movie = try await Self.export( file: file, to: url, codec: .h264, frameRate: .fromTimestamps( fallback: 10 ) )

        #expect( abs( movie.duration - 1.5 ) < 0.01 )
        #expect( movie.frames == 3 )
    }

    @Test
    func fallsBackWhenTheFileCarriesNoTimestamps() async throws
    {
        let file  = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 3, timestamps: nil )
        let url   = try TestUtilities.temporaryURL( named: "notrailer.mov" )
        let movie = try await Self.export( file: file, to: url, codec: .h264, frameRate: .fromTimestamps( fallback: 10 ) )

        #expect( abs( movie.duration - 0.3 ) < 0.01 )
    }

    @Test
    func fallsBackWhenTheTimestampsDoNotAdvance() async throws
    {
        // Frames stamped out of order, or all with the same instant, name no
        // rate at all.
        let backwards = [ Self.startTicks + Self.ticksPerSecond, Self.startTicks, Self.startTicks + Self.ticksPerSecond / 2 ]
        let repeated  = [ Self.startTicks, Self.startTicks, Self.startTicks ]

        try await TestUtilities.asyncForEach( [ backwards, repeated ] )
        {
            ticks in

            let file  = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 3, timestamps: ticks )
            let url   = try TestUtilities.temporaryURL( named: "unusable.mov" )
            let movie = try await Self.export( file: file, to: url, codec: .h264, frameRate: .fromTimestamps( fallback: 10 ) )

            #expect( abs( movie.duration - 0.3 ) < 0.01, "an unusable trailer does not fall back" )
        }
    }

    @Test
    func exportsAHighSpeedCaptureAtItsOwnRate() async throws
    {
        // SER is a high-speed format, and a thousand frames a second is an
        // ordinary planetary capture. Sixty of them is a movie sixty
        // milliseconds long, which round-trips exactly — the frame times are
        // stored at a resolution fine enough to keep them apart.
        let file  = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 60, timestamps: nil )
        let url   = try TestUtilities.temporaryURL( named: "fast.mov" )
        let movie = try await Self.export( file: file, to: url, codec: .proRes4444, frameRate: .constant( 1000 ) )

        #expect( movie.frames == 60 )
        #expect( abs( movie.duration - 0.06 ) < 0.001 )
    }

    @Test
    func rejectsAFrameRateNoMovieCanHold() async throws
    {
        // Both ends. Past 600 a second the frames land on each other and the
        // encoder drops them, which is measured rather than assumed; and a rate
        // small enough to put the last frame past the end of a movie's clock is
        // a trap rather than an error if it is not caught.
        let file = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 2, timestamps: nil )

        try await TestUtilities.asyncForEach( [ 30001.0, Double.greatestFiniteMagnitude / 2, 1e-300 ] )
        {
            rate in

            let url    = try TestUtilities.temporaryURL( named: "unrepresentable.mov" )
            let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .h264, frameRate: .constant( rate ), scaled: true ) )

            await Self.expectMovieExportFailure( containing: nil )
            {
                try await writer.write( file: file, to: url, progress: nil )
            }

            #expect( FileManager.default.fileExists( atPath: url.path ) == false, "a rate of \( rate ) leaves a file behind" )
        }
    }

    @Test
    func fallsBackWhenTheCaptureRanFasterThanTheTimesCanExpress() async throws
    {
        // Frames a hundredth of a millisecond apart is a hundred thousand a
        // second, past what the frame times can express, so the fallback answers
        // rather than the export failing.
        let ticks = ( 0 ..< 3 ).map { Self.startTicks + Int64( $0 ) * 100 }
        let file  = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 3, timestamps: ticks )
        let url   = try TestUtilities.temporaryURL( named: "toofast.mov" )
        let movie = try await Self.export( file: file, to: url, codec: .h264, frameRate: .fromTimestamps( fallback: 10 ) )

        #expect( abs( movie.duration - 0.3 ) < 0.01 )
        #expect( movie.frames == 3 )
    }

    // MARK: - Scaling

    @Test
    func scalingDecidesHowBrightTheMovieIs() async throws
    {
        // A 12-bit capture at full scale occupies 0...4095 of its container, so
        // unscaled it encodes to a movie that plays back nearly black. Both
        // settings are exported and compared, which is what gives the option
        // behavior a test rather than only a round trip through the struct.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.littleEndian       = 1
        fields.imageWidth         = 16
        fields.imageHeight        = 16
        fields.pixelDepthPerPlane = 12
        fields.frameCount         = 1

        // Every sample at the top of the 12-bit range.
        let frame = [ UInt8 ]( repeating: 0, count: fields.bytesPerFrame ).enumerated().map { $0.offset % 2 == 0 ? UInt8( 0xFF ) : UInt8( 0x0F ) }
        let file  = try SERFile( data: TestUtilities.File( header: fields, frames: [ frame ], timestamps: nil ).data, options: .strict )

        let bright = try await Self.firstAndLastRow( at: Self.written( file: file, scaled: true,  named: "scaled.mov" ) )
        let dark   = try await Self.firstAndLastRow( at: Self.written( file: file, scaled: false, named: "unscaled.mov" ) )

        #expect( bright.first > 200, "a scaled 12-bit frame does not reach full scale" )
        #expect( dark.first   < 50,  "an unscaled 12-bit frame is not left near black" )
    }

    // MARK: - Progress and cancellation

    @Test
    func reportsProgressOnceForEveryFrame() async throws
    {
        let file   = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 4, timestamps: nil )
        let url    = try TestUtilities.temporaryURL( named: "progress.mov" )
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .h264, frameRate: .constant( 10 ), scaled: true ) )

        let reported = Reported()

        try await writer.write( file: file, to: url )
        {
            reported.append( $0 )
        }

        #expect( reported.values == [ 0.25, 0.5, 0.75, 1.0 ] )
    }

    @Test
    func cancellingTheTaskStopsTheExport() async throws
    {
        let file   = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 8, timestamps: nil )
        let url    = try TestUtilities.temporaryURL( named: "cancelled.mov" )
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .h264, frameRate: .constant( 10 ), scaled: true ) )

        // Cancelled before the task's body ever runs, so the writer observes it
        // at its first check rather than at whichever frame the race lands on.
        let reported = Reported()

        let task = Task
        {
            try await writer.write( file: file, to: url )
            {
                reported.append( $0 )
            }
        }

        task.cancel()

        await #expect( throws: CancellationError.self )
        {
            try await task.value
        }

        // Not a single frame was written, which is what pins the check as
        // happening *before* the first frame: without it the export runs on
        // until the readiness wait notices instead, several frames later.
        #expect( reported.values.isEmpty )

        // And nothing was left at the destination.
        #expect( FileManager.default.fileExists( atPath: url.path ) == false )
    }

    @Test
    func cancellingPartWayThroughLeavesNothingBehind() async throws
    {
        // The other half of the guarantee: a cancellation that lands after some
        // frames have already been encoded still clears the destination.
        let file   = try Self.monoFile( colorID: 0, width: 64, height: 64, frames: 40, timestamps: nil )
        let url    = try TestUtilities.temporaryURL( named: "cancelled-late.mov" )
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .proRes4444, frameRate: .constant( 10 ), scaled: true ) )
        let box    = TaskBox()

        box.task = Task
        {
            try await writer.write( file: file, to: url )
            {
                // Cancels itself once the export is genuinely under way.
                if $0 > 0.1
                {
                    box.task?.cancel()
                }
            }
        }

        await #expect( throws: CancellationError.self )
        {
            try await box.task?.value
        }

        #expect( FileManager.default.fileExists( atPath: url.path ) == false )
    }

    // MARK: - Failure paths

    @Test
    func rejectsADestinationItCannotWrite() async throws
    {
        let file   = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 1, timestamps: nil )
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .h264, frameRate: .constant( 10 ), scaled: true ) )

        await Self.expectMovieExportFailure( containing: nil )
        {
            try await writer.write( file: file, to: URL( fileURLWithPath: "/no-such-directory-here/out.mov" ), progress: nil )
        }
    }

    @Test
    func rejectsADestinationThatAlreadyExists() async throws
    {
        // The writer does not overwrite: a destination already holding
        // something is reported rather than replaced.
        let file   = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 1, timestamps: nil )
        let url    = try TestUtilities.temporaryFile( containing: Data( [ 1, 2, 3 ] ), named: "existing.mov" )
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .h264, frameRate: .constant( 10 ), scaled: true ) )

        await Self.expectMovieExportFailure( containing: nil )
        {
            try await writer.write( file: file, to: url, progress: nil )
        }
    }

    @Test
    func rejectsAFileWithNoFrames() async throws
    {
        // There is no movie to write, and an empty one is not a valid movie.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = 0
        fields.imageWidth  = 16
        fields.imageHeight = 16
        fields.frameCount  = 0

        let file   = try SERFile( data: TestUtilities.File( header: fields, frames: [], timestamps: nil ).data, options: .strict )
        let url    = try TestUtilities.temporaryURL( named: "empty.mov" )
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .h264, frameRate: .constant( 10 ), scaled: true ) )

        await Self.expectMovieExportFailure( containing: "holds no frames" )
        {
            try await writer.write( file: file, to: url, progress: nil )
        }
    }

    @Test
    func rejectsAFrameRateThatNamesNoPace() async throws
    {
        let file   = try Self.monoFile( colorID: 0, width: 16, height: 16, frames: 1, timestamps: nil )
        let url    = try TestUtilities.temporaryURL( named: "zero.mov" )
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .h264, frameRate: .constant( 0 ), scaled: true ) )

        await Self.expectMovieExportFailure( containing: "names no pace" )
        {
            try await writer.write( file: file, to: url, progress: nil )
        }
    }

    // MARK: - Description

    @Test
    func describesItself() async throws
    {
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .hevc, frameRate: .constant( 25 ), scaled: true ) )

        #expect( writer.description.contains( "HEVC" ) )
    }

    // MARK: - Helpers

    /// Asserts that a body fails with ``SERError/movieExportFailed(reason:)``.
    ///
    /// Asserted on the case and its reason rather than on `SERError` alone: the
    /// milestone requires movie failures to surface as this case carrying
    /// AVFoundation's own reason, and every other case in the enum would satisfy
    /// a test that only names the type.
    ///
    /// - Parameters:
    ///   - fragment: Text the reason must contain, or `nil` for the failures
    ///               AVFoundation words itself, whose reason is only required to
    ///               say something.
    ///   - body:     The work expected to fail.
    private static func expectMovieExportFailure( containing fragment: String?, _ body: () async throws -> Void ) async
    {
        do
        {
            try await body()

            Issue.record( "The export was expected to fail and did not" )
        }
        catch let error as SERError
        {
            guard case .movieExportFailed( let reason ) = error
            else
            {
                Issue.record( "The export failed with \( error ) rather than a movie export failure" )

                return
            }

            guard let fragment
            else
            {
                #expect( reason.isEmpty == false, "The failure carries no reason at all" )

                return
            }

            #expect( reason.contains( fragment ), "The reason \"\( reason )\" does not mention \"\( fragment )\"" )
        }
        catch
        {
            Issue.record( "The export failed with \( error ), which is not a SERError" )
        }
    }

    /// A synthetic file whose frames each hold their own index.
    ///
    /// - Parameters:
    ///   - colorID:    The raw color ID the header declares.
    ///   - width:      The image width, in pixels.
    ///   - height:     The image height, in pixels.
    ///   - frames:     The number of frames to write.
    ///   - timestamps: The trailer's tick values, or `nil` for no trailer.
    /// - Returns: The parsed file.
    /// - Throws: Any error raised while parsing.
    private static func monoFile( colorID: Int32, width: Int32, height: Int32, frames: Int32, timestamps: [ Int64 ]? ) throws -> SERFile
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID     = colorID
        fields.imageWidth  = width
        fields.imageHeight = height
        fields.frameCount  = frames
        fields.dateTime    = timestamps == nil ? 0 : Self.startTicks
        fields.dateTimeUTC = timestamps == nil ? 0 : Self.startTicks

        let bytes = TestUtilities.indexedFrames( count: Int( frames ), bytesPerFrame: fields.bytesPerFrame )

        return try SERFile( data: TestUtilities.File( header: fields, frames: bytes, timestamps: timestamps ).data, options: .strict )
    }

    /// Exports a file through ProRes 4444, at one scaling setting or the other.
    ///
    /// ProRes rather than a lossy codec, so the pixels read back are the ones
    /// written and the comparison is about the scaling rather than the encoder.
    ///
    /// - Parameters:
    ///   - file:   The file to export.
    ///   - scaled: Whether to stretch the sample range over the output's.
    ///   - named:  The destination's file name.
    /// - Returns: The URL the movie was written to.
    /// - Throws: Any error raised while exporting.
    private static func written( file: SERFile, scaled: Bool, named: String ) async throws -> URL
    {
        let url    = try TestUtilities.temporaryURL( named: named )
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .proRes4444, frameRate: .constant( 10 ), scaled: scaled ) )

        try await writer.write( file: file, to: url, progress: nil )

        return url
    }

    /// Exports a file and reads the movie back.
    ///
    /// - Parameters:
    ///   - file:      The file to export.
    ///   - url:       The destination.
    ///   - codec:     The codec to encode with.
    ///   - frameRate: The pace to write the frames at.
    /// - Returns: What the written movie reports about itself.
    /// - Throws: Any error raised while exporting or reading back.
    private static func export( file: SERFile, to url: URL, codec: SERMovieCodec, frameRate: SERMovieFrameRate ) async throws -> ( duration: Double, width: Int, height: Int, frames: Int )
    {
        let writer = SERMovieWriter( options: SERMovieExportOptions( codec: codec, frameRate: frameRate, scaled: true ) )

        try await writer.write( file: file, to: url, progress: nil )

        return try await Self.movie( at: url )
    }

    /// The blue component of the first pixel of the first and last rows of a
    /// movie's opening frame.
    ///
    /// Enough to tell a frame written the right way up from a flipped one,
    /// without asserting on a whole decoded image.
    ///
    /// - Parameter url: The movie's location.
    /// - Returns: The two components, top row first.
    /// - Throws: An expectation failure if the movie carries no readable frame,
    ///           or any error raised while reading.
    private static func firstAndLastRow( at url: URL ) async throws -> ( first: UInt8, last: UInt8 )
    {
        let asset  = AVURLAsset( url: url )
        let track  = try #require( try await asset.loadTracks( withMediaType: .video ).first )
        let reader = try AVAssetReader( asset: asset )
        let output = AVAssetReaderTrackOutput( track: track, outputSettings: [ kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA ] )

        reader.add( output )
        reader.startReading()

        let sample = try #require( output.copyNextSampleBuffer() )
        let buffer = try #require( CMSampleBufferGetImageBuffer( sample ) )

        CVPixelBufferLockBaseAddress( buffer, .readOnly )

        defer
        {
            CVPixelBufferUnlockBaseAddress( buffer, .readOnly )
        }

        let base     = try #require( CVPixelBufferGetBaseAddress( buffer ) )
        let rowBytes = CVPixelBufferGetBytesPerRow( buffer )
        let height   = CVPixelBufferGetHeight( buffer )

        return (
            base.loadUnaligned( fromByteOffset: 0, as: UInt8.self ),
            base.loadUnaligned( fromByteOffset: ( height - 1 ) * rowBytes, as: UInt8.self )
        )
    }

    /// The blue component of the first pixel of every frame of a movie, in
    /// order.
    ///
    /// - Parameter url: The movie's location.
    /// - Returns: One component per frame the movie holds.
    /// - Throws: An expectation failure if the movie carries no video track, or
    ///           any error raised while reading.
    private static func frameLevels( at url: URL ) async throws -> [ UInt8 ]
    {
        let asset  = AVURLAsset( url: url )
        let track  = try #require( try await asset.loadTracks( withMediaType: .video ).first )
        let reader = try AVAssetReader( asset: asset )
        let output = AVAssetReaderTrackOutput( track: track, outputSettings: [ kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA ] )

        reader.add( output )
        reader.startReading()

        defer
        {
            reader.cancelReading()
        }

        var levels: [ UInt8 ] = []

        // Walked by hand: the reader hands back one buffer at a time until it
        // runs out, which is a `while let` and not a sequence.
        while let sample = output.copyNextSampleBuffer()
        {
            guard let buffer = CMSampleBufferGetImageBuffer( sample )
            else
            {
                continue
            }

            CVPixelBufferLockBaseAddress( buffer, .readOnly )

            if let base = CVPixelBufferGetBaseAddress( buffer )
            {
                levels.append( base.loadUnaligned( fromByteOffset: 0, as: UInt8.self ) )
            }

            CVPixelBufferUnlockBaseAddress( buffer, .readOnly )
        }

        return levels
    }

    /// What a written movie reports about itself.
    ///
    /// - Parameter url: The movie's location.
    /// - Returns: Its duration in seconds, its pixel dimensions, and the number
    ///            of frames actually encoded, counted by reading them.
    /// - Throws: An expectation failure if the movie carries no video track, or
    ///           any error raised while reading.
    private static func movie( at url: URL ) async throws -> ( duration: Double, width: Int, height: Int, frames: Int )
    {
        let asset    = AVURLAsset( url: url )
        let duration = try await asset.load( .duration )
        let track    = try #require( try await asset.loadTracks( withMediaType: .video ).first )
        let size     = try await track.load( .naturalSize )
        let reader   = try AVAssetReader( asset: asset )
        let output   = AVAssetReaderTrackOutput( track: track, outputSettings: nil )

        reader.add( output )
        reader.startReading()

        var frames = 0

        // Walked by hand: the reader hands back one buffer at a time until it
        // runs out, which is a `while let` and not a sequence.
        while let sample = output.copyNextSampleBuffer()
        {
            frames += CMSampleBufferGetNumSamples( sample )
        }

        reader.cancelReading()

        return ( duration.seconds, Int( size.width ), Int( size.height ), frames )
    }
}

#endif
