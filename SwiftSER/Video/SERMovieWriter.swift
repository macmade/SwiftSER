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
import CoreGraphics
import CoreVideo
import Foundation

/// Encodes a whole SER sequence into a QuickTime movie.
///
/// Frames are read, converted and appended one at a time, so a capture far
/// larger than memory still exports: only one frame is ever materialized.
///
/// ```swift
/// let writer = SERMovieWriter( options: SERMovieExportOptions( codec: .h264, frameRate: .constant( 30 ), scaled: true ) )
///
/// try await writer.write( file: file, to: url )
/// {
///     print( "\( Int( $0 * 100 ) )%" )
/// }
/// ```
///
/// Cancelling the task running the export stops it, discards the partial movie
/// and throws `CancellationError` — up until the last frame is appended.
/// Finishing a movie cannot itself be cancelled, so a cancellation arriving
/// during it is not observed and the export succeeds.
///
/// - Note: A ``SERFile`` is not `Sendable` and this type is not isolated to any
///         actor, so an actor-isolated caller cannot hand over a file it keeps:
///         open the file where the export runs, or give up ownership of it. That
///         is the same rule that stops a file being read from two threads at
///         once, and the compiler enforces it.
public struct SERMovieWriter: Sendable, CustomStringConvertible
{
    /// The timescale presentation times are expressed in.
    ///
    /// 30000 rather than QuickTime's traditional 600, because SER is a
    /// high-speed format: a planetary capture at 1000 frames a second is
    /// ordinary, and a 600 scale cannot express it — two frames would land on
    /// one tick. It divides every rate that matters exactly, the common ones
    /// (24, 25, 30, 48, 50, 60, 120, 240) and the fast ones (1000, 6000) alike,
    /// so no frame time is rounded.
    private static let timescale: CMTimeScale = 30000

    /// The fastest pace a movie can be written at, in frames per second.
    ///
    /// The timescale, because two frames cannot share a tick. Beyond it the
    /// export does not degrade quietly — ``AVAssetWriter`` refuses the frame
    /// whose time collides with its predecessor and the whole export fails,
    /// which was measured at 700 frames a second against a 600 scale before the
    /// scale was raised.
    private static let maximumFrameRate = Double( SERMovieWriter.timescale )

    /// How long to wait before asking again whether the input can take more.
    ///
    /// Only reached when the encoder is behind, and only ever suspends this
    /// task rather than blocking a thread.
    private static let readinessPollInterval = Duration.milliseconds( 1 )

    /// How the sequence is encoded.
    public let options: SERMovieExportOptions

    /// Creates a movie writer.
    ///
    /// - Parameter options: How to encode the sequence.
    public init( options: SERMovieExportOptions )
    {
        self.options = options
    }

    /// Encodes a file's frames into a movie.
    ///
    /// Each frame goes out as ``SERFile/cgImage(ofFrame:scaled:)`` renders it,
    /// so a mosaic is debayered through whichever implementation the file's
    /// ``SERFile/debayering`` names, and everything else is rendered from its
    /// own planes. The movie's pixels are 8-bit whatever the capture's depth,
    /// which is what the pixel format the encoders take can carry.
    ///
    /// - Important: The destination must not already exist. A movie is not
    ///   written over anything; an occupied destination is reported instead.
    ///
    /// - Note: A movie only a few milliseconds long is not read back reliably,
    ///   whatever it was written with — a handful of frames at a thousand a
    ///   second comes back one or two short, and at six thousand not at all.
    ///   That is the reader's floor rather than anything the writer does, and it
    ///   is reached only by exporting a very short capture at a very fast rate;
    ///   the same frames at a rate anyone would watch are all there. Measured
    ///   across every codec.
    ///
    /// - Parameters:
    ///   - file:     The capture to encode.
    ///   - url:      Where to write the movie. Must not already exist.
    ///   - progress: Called after each frame is appended, with the fraction
    ///               written so far, ending at exactly 1. Called on whichever
    ///               executor is running the export, so it must not block.
    /// - Throws: `CancellationError` if the task is cancelled, in which case
    ///           nothing is left at `url`;
    ///           ``SERError/movieExportFailed(reason:)`` if the file holds no
    ///           frames, if the frame rate names no pace a timeline can express,
    ///           or if AVFoundation declines any step, carrying its own reason;
    ///           or anything ``SERFile/cgImage(ofFrame:scaled:)`` raises for a
    ///           frame. Nothing is left at `url` in any of those cases either.
    public func write( file: SERFile, to url: URL, progress: ( @Sendable ( Double ) -> Void )? ) async throws
    {
        guard file.frameCount > 0
        else
        {
            throw SERError.movieExportFailed( reason: "The file holds no frames to write" )
        }

        let rate = self.frameRate( of: file )

        guard rate > 0, rate.isFinite, rate <= SERMovieWriter.maximumFrameRate
        else
        {
            throw SERError.movieExportFailed( reason: "A frame rate of \( rate ) names no pace a movie can be written at, which is anything from just above zero to \( SERMovieWriter.maximumFrameRate ) frames per second" )
        }

        let width  = Int( file.header.imageWidth )
        let height = Int( file.header.imageHeight )

        // A macroblock codec rounds an odd dimension down to the next even one,
        // and a dimension of 1 therefore rounds to nothing at all: the export
        // reports success and writes a movie no reader will open. Refused here
        // rather than left to be discovered on playback.
        guard self.options.codec.preservesOddDimensions || ( width > 1 && height > 1 )
        else
        {
            throw SERError.movieExportFailed( reason: "\( self.options.codec ) cannot write a \( width )x\( height ) movie, since it rounds a dimension of 1 down to nothing" )
        }
        let writer = try self.assetWriter( at: url )
        let input  = self.assetWriterInput( width: width, height: height )

        guard writer.canAdd( input )
        else
        {
            throw SERError.movieExportFailed( reason: "A \( width )x\( height ) \( self.options.codec ) track cannot be written" )
        }

        writer.add( input )

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput:            input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String:           width,
                kCVPixelBufferHeightKey as String:          height,
            ]
        )

        guard writer.startWriting()
        else
        {
            throw SERError.movieExportFailed( reason: writer.error?.localizedDescription ?? "The movie could not be started" )
        }

        writer.startSession( atSourceTime: .zero )

        do
        {
            try await self.append( frames: file, to: adaptor, input: input, rate: rate, progress: progress )

            input.markAsFinished()
            writer.endSession( atSourceTime: try self.time( ofFrame: file.frameCount, rate: rate ) )

            await writer.finishWriting()

            guard writer.status == .completed
            else
            {
                throw SERError.movieExportFailed( reason: writer.error?.localizedDescription ?? "The movie could not be finished" )
            }
        }
        catch
        {
            SERMovieWriter.discard( writer, at: url )

            throw error
        }
    }

    /// Abandons a movie, leaving nothing at its destination.
    ///
    /// `cancelWriting` is documented as a no-op once the writer has failed or
    /// completed, and a writer that failed mid-export has already put bytes on
    /// disk, so the file is removed as well rather than instead: cancelling is
    /// what stops a writer still in progress, and the removal is what clears up
    /// after one that is not. Leaving the debris would also poison a retry,
    /// since a destination that already exists is refused.
    ///
    /// - Parameters:
    ///   - writer: The writer to abandon.
    ///   - url:    The destination to clear.
    private static func discard( _ writer: AVAssetWriter, at url: URL )
    {
        if writer.status == .writing
        {
            writer.cancelWriting()
        }

        // Nothing to report: this runs while another error is on its way out,
        // and that error is the one worth telling the caller about.
        try? FileManager.default.removeItem( at: url )
    }

    /// Appends every frame of a file, respecting the encoder's back-pressure.
    ///
    /// - Parameters:
    ///   - file:     The capture to encode.
    ///   - adaptor:  The adaptor to append pixel buffers through.
    ///   - input:    The adaptor's input, whose readiness paces the loop.
    ///   - rate:     The frame rate, in frames per second.
    ///   - progress: Called after each frame is appended.
    /// - Throws: `CancellationError` if the task is cancelled;
    ///           ``SERError/movieExportFailed(reason:)`` if a buffer cannot be
    ///           made or appended; or anything rendering a frame raises.
    private func append( frames file: SERFile, to adaptor: AVAssetWriterInputPixelBufferAdaptor, input: AVAssetWriterInput, rate: Double, progress: ( @Sendable ( Double ) -> Void )? ) async throws
    {
        // Walked by index rather than by iterating the file's frames: the frame
        // is rendered through `SERFile`, which is what applies the debayering,
        // and the index is needed for the presentation time in any case.
        for index in 0 ..< file.frameCount
        {
            // Checked before the first frame as well as between them, so a task
            // cancelled before the export ever runs stops without writing.
            try Task.checkCancellation()

            // The documented signal that the encoder has caught up. Awaited
            // rather than spun on, so nothing is blocked while it works.
            while input.isReadyForMoreMediaData == false
            {
                try await Task.sleep( for: SERMovieWriter.readinessPollInterval )
            }

            // Nothing else in the loop suspends when the encoder keeps up, and
            // an export of thousands of frames would otherwise hold its thread
            // from start to finish, starving whatever else the caller is running.
            await Task.yield()

            let buffer = try self.pixelBuffer( ofFrame: index, of: file, from: adaptor )

            guard adaptor.append( buffer, withPresentationTime: try self.time( ofFrame: index, rate: rate ) )
            else
            {
                throw SERError.movieExportFailed( reason: "Frame \( index ) could not be appended" )
            }

            progress?( Double( index + 1 ) / Double( file.frameCount ) )
        }
    }

    /// Renders one frame into a pixel buffer the encoder can take.
    ///
    /// - Parameters:
    ///   - index:   The frame's index.
    ///   - file:    The capture the frame belongs to.
    ///   - adaptor: The adaptor whose pool the buffer is taken from.
    /// - Returns: The frame, as 32-bit BGRA.
    /// - Throws: ``SERError/movieExportFailed(reason:)`` if no buffer can be
    ///           made or drawn into, or anything rendering the frame raises.
    private func pixelBuffer( ofFrame index: Int, of file: SERFile, from adaptor: AVAssetWriterInputPixelBufferAdaptor ) throws -> CVPixelBuffer
    {
        let image = try file.cgImage( ofFrame: index, scaled: self.options.scaled )

        guard let pool = adaptor.pixelBufferPool
        else
        {
            throw SERError.movieExportFailed( reason: "The encoder offers no pixel buffer pool" )
        }

        var created: CVPixelBuffer?

        let status = CVPixelBufferPoolCreatePixelBuffer( nil, pool, &created )

        guard status == kCVReturnSuccess, let buffer = created
        else
        {
            throw SERError.movieExportFailed( reason: "A pixel buffer for frame \( index ) could not be created (\( status ))" )
        }

        CVPixelBufferLockBaseAddress( buffer, [] )

        defer
        {
            CVPixelBufferUnlockBaseAddress( buffer, [] )
        }

        guard let base = CVPixelBufferGetBaseAddress( buffer )
        else
        {
            throw SERError.movieExportFailed( reason: "The pixel buffer for frame \( index ) has no storage" )
        }

        let width  = CVPixelBufferGetWidth( buffer )
        let height = CVPixelBufferGetHeight( buffer )

        // 32-bit BGRA is the little-endian reading of a 32-bit word whose alpha
        // comes first, which is how Core Graphics has to be told to describe it.
        // `order32Little` rather than `CGBitmapInfo.byteOrder32Little`: the two
        // name the same bits, but the second is soft-deprecated.
        guard let context = CGContext(
            data:             base,
            width:            width,
            height:           height,
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow( buffer ),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGImageAlphaInfo.noneSkipFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue
        )
        else
        {
            throw SERError.movieExportFailed( reason: "Frame \( index ) could not be drawn into a \( width )x\( height ) buffer" )
        }

        context.draw( image, in: CGRect( x: 0, y: 0, width: width, height: height ) )

        return buffer
    }

    /// The presentation time of a frame.
    ///
    /// - Parameters:
    ///   - index: The frame's index. Passing the frame count gives the time one
    ///            frame past the last, which is where the session ends.
    ///   - rate:  The frame rate, in frames per second.
    /// - Returns: The instant the frame is shown at.
    /// - Throws: ``SERError/movieExportFailed(reason:)`` if the timeline runs
    ///           past what a `CMTime` can hold, which a rate small enough to
    ///           spread a capture over millions of years does.
    private func time( ofFrame index: Int, rate: Double ) throws -> CMTime
    {
        let ticks = ( Double( index ) * Double( SERMovieWriter.timescale ) / rate ).rounded()

        // Checked rather than converted: `CMTimeValue` is a 64-bit integer and
        // the conversion from `Double` traps rather than saturating, which the
        // rate alone does not bound — a positive rate can still be small enough
        // to put the last frame past the end of time.
        guard ticks >= 0, ticks < Double( CMTimeValue.max )
        else
        {
            throw SERError.movieExportFailed( reason: "A frame rate of \( rate ) puts frame \( index ) beyond what a movie timeline can express" )
        }

        return CMTime( value: CMTimeValue( ticks ), timescale: SERMovieWriter.timescale )
    }

    /// The rate a file's frames are written at.
    ///
    /// - Parameter file: The capture to encode.
    /// - Returns: The configured constant rate, or the average rate the trailer
    ///            records, falling back where it names none — see
    ///            ``SERMovieFrameRate/fromTimestamps(fallback:)``.
    private func frameRate( of file: SERFile ) -> Double
    {
        switch self.options.frameRate
        {
            case .constant( let rate ):

                return rate

            case .fromTimestamps( let fallback ):

                return self.recordedFrameRate( of: file ) ?? fallback
        }
    }

    /// The average rate a capture's trailer records.
    ///
    /// Measured from the first stamped frame to the last rather than by
    /// averaging every interval, so frames that wander out of order in between
    /// still yield the pace the capture ran at.
    ///
    /// - Parameter file: The capture to measure.
    /// - Returns: The rate in frames per second, or `nil` when the trailer names
    ///            none.
    private func recordedFrameRate( of file: SERFile ) -> Double?
    {
        // Paired with their frame indices, since the span between the first and
        // last stamps covers every frame between them and not only the stamped
        // ones. A trailer with holes in it would otherwise read as slower than
        // the capture ran: half the stamps over the whole span is half the rate.
        let stamped = file.timestamps.enumerated().compactMap
        {
            entry in

            entry.element.map { ( index: entry.offset, date: $0 ) }
        }

        guard stamped.count > 1, let first = stamped.first, let last = stamped.last
        else
        {
            return nil
        }

        let span = last.date.timeIntervalSince( first.date )

        guard span > 0
        else
        {
            return nil
        }

        let rate = Double( last.index - first.index ) / span

        // A capture recorded faster than a movie can be written names a pace
        // that cannot be honoured, so it is treated like a trailer that names
        // none at all and answers to the fallback. Failing the export instead
        // would punish exactly the high-speed captures the format is used for.
        guard rate <= SERMovieWriter.maximumFrameRate
        else
        {
            return nil
        }

        return rate
    }

    /// The asset writer a movie is written through.
    ///
    /// - Parameter url: Where to write the movie.
    /// - Returns: The writer.
    /// - Throws: ``SERError/movieExportFailed(reason:)`` carrying AVFoundation's
    ///           own reason, which is what an occupied or unreachable
    ///           destination reports through.
    private func assetWriter( at url: URL ) throws -> AVAssetWriter
    {
        do
        {
            return try AVAssetWriter( outputURL: url, fileType: .mov )
        }
        catch
        {
            throw SERError.movieExportFailed( reason: error.localizedDescription )
        }
    }

    /// The input a movie's video track is written through.
    ///
    /// - Parameters:
    ///   - width:  The frame width, in pixels.
    ///   - height: The frame height, in pixels.
    /// - Returns: The input, told that its source is not real-time, which is
    ///            what tunes ``AVAssetWriterInput/isReadyForMoreMediaData`` for
    ///            a pull-style source: the flag then reflects the encoder's
    ///            appetite rather than a real-time deadline.
    private func assetWriterInput( width: Int, height: Int ) -> AVAssetWriterInput
    {
        let input = AVAssetWriterInput(
            mediaType:      .video,
            outputSettings: [
                AVVideoCodecKey:  self.options.codec.videoCodecType,
                AVVideoWidthKey:  width,
                AVVideoHeightKey: height,
            ]
        )

        // A SER capture is a file being read, not a camera. The flag does not
        // make the input keep frames — it never drops any — it decides how
        // `isReadyForMoreMediaData` is computed, and this is the setting that
        // suits a source which can be asked for the next frame whenever the
        // encoder is ready for it.
        input.expectsMediaDataInRealTime = false

        // The track's own resolution, which is a separate thing from the
        // presentation times handed to it. Its default of 0 lets QuickTime pick,
        // and it picks this same 600; stating it means the times written and the
        // scale they are stored at cannot drift apart.
        input.mediaTimeScale = SERMovieWriter.timescale

        return input
    }

    /// A human-readable summary of how the writer is configured.
    ///
    /// Kept to a single line, as the value types are.
    public var description: String
    {
        "SER movie writer (\( self.options ))"
    }
}

#endif
