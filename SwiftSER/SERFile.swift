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

/// A parsed SER file.
///
/// Opening a file parses its 178-byte header, reconciles the frame count the
/// header declares against the bytes actually present, and locates the optional
/// trailer of per-frame timestamps. Frame pixel data is *not* read: frames are
/// addressed by byte offset on demand, so a multi-gigabyte capture can be
/// inspected without being loaded — as far as the platform allows, since
/// `.mappedIfSafe` declines to map some files and reads them instead.
///
/// The trailer's position is defined by the frame count the *header* declares,
/// so a file holding more frames than it declares has its surplus frames read
/// as timestamps. That follows from the format itself, which offers no other
/// way to locate the trailer.
///
/// The parsed timestamps are cached on first access, so a file is not safe to
/// use from several threads at once and is not `Sendable`.
public class SERFile: CustomStringConvertible
{
    /// The number of bytes one timestamp occupies in the trailer.
    public static let timestampSize = 8

    /// The file's parsed header.
    public let header: SERHeader

    /// The options the file was parsed with.
    ///
    /// Retained because frame and timestamp decoding happen on demand, after
    /// parsing, and must apply the same leniency.
    public let options: SERParsingOptions

    /// The number of frames the file actually holds.
    ///
    /// Normally ``SERHeader/frameCount``. When the header declares more frames
    /// than the file has bytes for and
    /// ``SERParsingOptions/allowFrameCountMismatch`` is set, this is the number
    /// of whole frames the file really holds, established by finding where the
    /// timestamp trailer begins. Comparing the two records the discrepancy.
    public let frameCount: Int

    /// Whether the file carries at least one whole per-frame timestamp.
    ///
    /// A tail too short to hold even one timestamp reports `false` here, though
    /// it is still treated as a truncated trailer for the purpose of
    /// ``SERParsingOptions/allowShortTrailer``.
    ///
    /// Unlike ``SERHeader/declaresTimestampTrailer``, which only reports what
    /// the header's start date implies, this is confirmed against the file's
    /// length and honours ``SERParsingOptions/allowInvalidTimestamps`` when
    /// reading that start date.
    public let hasTimestampTrailer: Bool

    /// The file's complete bytes.
    private let data: Data

    /// The offset at which the timestamp trailer begins.
    private let trailerOffset: Int

    /// The number of timestamps the trailer holds, never more than
    /// ``frameCount``.
    private let trailerCount: Int

    /// The parsed timestamps, once someone has asked for them.
    internal private( set ) var cachedTimestamps: [ Date? ]?

    /// The local reading of the clock when the image stream started, or `nil`
    /// if the header does not record a valid one.
    ///
    /// - Important: This is a wall-clock reading, not an instant. The format
    ///   records the capture machine's local time with no time zone attached,
    ///   so the value is expressed here as though that reading were UTC:
    ///   rendering it in any other time zone shifts it a second time. Use
    ///   ``startTimeUTC`` for the instant the capture began, and ``utcOffset``
    ///   for the zone the capture machine was in.
    public var startTime: Date?
    {
        SERTimestamp( rawValue: self.header.dateTime, options: self.options ).date
    }

    /// The instant the image stream started, or `nil` if the header does not
    /// record a valid one.
    public var startTimeUTC: Date?
    {
        SERTimestamp( rawValue: self.header.dateTimeUTC, options: self.options ).date
    }

    /// How far the capture machine's local time ran ahead of UTC, or `nil` if
    /// the header does not record both start times.
    ///
    /// The difference between the two start-time fields is the only time-zone
    /// information the format carries, and it is what makes ``startTime``
    /// usable: added to ``startTimeUTC``, it reproduces the local reading.
    public var utcOffset: TimeInterval?
    {
        let local = SERTimestamp( rawValue: self.header.dateTime,    options: self.options )
        let utc   = SERTimestamp( rawValue: self.header.dateTimeUTC, options: self.options )

        guard local.date != nil, utc.date != nil
        else
        {
            return nil
        }

        return Double( local.ticks - utc.ticks ) / Double( SERTimestamp.ticksPerSecond )
    }

    /// The UTC capture time of each frame, in frame order.
    ///
    /// Always holds exactly ``frameCount`` entries, so it can be indexed by
    /// frame index. An entry is `nil` when the file carries no trailer, when a
    /// short trailer stops before that frame, or when the stored value names no
    /// valid instant.
    ///
    /// Parsed on first access and cached from then on.
    public var timestamps: [ Date? ]
    {
        if let cached = self.cachedTimestamps
        {
            return cached
        }

        let parsed = self.parseTimestamps()

        self.cachedTimestamps = parsed

        return parsed
    }

    /// Reads and parses a SER file from a file URL.
    ///
    /// - Parameters:
    ///   - url:     The location of the file to read.
    ///   - options: The parsing options to apply.
    /// - Throws: ``SERError/invalidFileURL(url:)`` if the URL is missing or a
    ///           directory, ``SERError/cannotReadFile(url:)`` if the contents
    ///           cannot be read, or any ``SERError`` raised while parsing the
    ///           data.
    /// - Note: The file is memory-mapped when safe (`.mappedIfSafe`). If another
    ///         process truncates the file while it is being read, accessing the
    ///         vanished pages can raise `SIGBUS` and terminate the process,
    ///         which no Swift error handling can intercept.
    public convenience init( url: URL, options: SERParsingOptions ) throws
    {
        let data: Data

        do
        {
            data = try Data( contentsOf: url, options: .mappedIfSafe )
        }
        catch
        {
            // Classify the failure only after attempting the read, so there is
            // no time-of-check/time-of-use gap: a missing path or a directory is
            // an invalid URL, anything else is an unreadable file.
            var isDir: ObjCBool = false

            if FileManager.default.fileExists( atPath: url.path, isDirectory: &isDir ) == false || isDir.boolValue
            {
                throw SERError.invalidFileURL( url: url )
            }

            throw SERError.cannotReadFile( url: url )
        }

        try self.init( data: data, options: options )
    }

    /// Parses a SER file from raw bytes.
    ///
    /// - Parameters:
    ///   - data:    The complete file contents.
    ///   - options: The parsing options to apply.
    /// - Throws: ``SERError/invalidFrameData(reason:)`` if the file holds fewer
    ///           frames than the header declares and
    ///           ``SERParsingOptions/allowFrameCountMismatch`` is not set;
    ///           ``SERError/invalidTrailerData(reason:)`` if an expected
    ///           timestamp trailer is missing or short without
    ///           ``SERParsingOptions/allowMissingTrailer`` or
    ///           ``SERParsingOptions/allowShortTrailer``; or any ``SERError``
    ///           raised while parsing the header.
    public init( data: Data, options: SERParsingOptions ) throws
    {
        let header         = try SERHeader( data: data, options: options )
        let payloadLength  = data.count - SERHeader.size
        let startTimestamp = SERTimestamp( rawValue: header.dateTime, options: options )

        // The specification ties the trailer's presence to the start date being
        // positive, not to its naming a representable instant, so this tests
        // the ticks rather than the date. A positive but out-of-range value
        // still means the trailer is there, and its bytes must not end up
        // addressed as frames.
        let expectsTrailer = startTimestamp.ticks > 0

        // The header only bounds a single frame's size; the whole payload can
        // still overflow at a frame count the header happily accepts.
        let ( declaredLength, overflow ) = Int( header.frameCount ).multipliedReportingOverflow( by: header.bytesPerFrame )

        if overflow || declaredLength > payloadLength
        {
            guard options.contains( .allowFrameCountMismatch )
            else
            {
                throw SERError.invalidFrameData( reason: "The header declares \( header.frameCount ) frames of \( header.bytesPerFrame ) bytes, which \( payloadLength ) bytes cannot hold" )
            }

            self.frameCount = SERFile.frameCount(
                fittingIn:     payloadLength,
                of:            data,
                bytesPerFrame: header.bytesPerFrame,
                withTrailer:   expectsTrailer,
                notBefore:     SERFile.trailerAnchor( local: startTimestamp, utc: SERTimestamp( rawValue: header.dateTimeUTC, options: options ) ),
                options:       options
            )
        }
        else
        {
            self.frameCount = Int( header.frameCount )
        }

        // Both branches bound the frame count by the payload the file really
        // holds, so this cannot overflow.
        let imageDataLength = self.frameCount * header.bytesPerFrame
        let trailerOffset   = SERHeader.size + imageDataLength
        let trailerLength   = data.count - trailerOffset
        // Qualified, since conforming to `Sequence` brings a `min` of its own
        // into the type's scope.
        let storedCount     = expectsTrailer ? Swift.min( trailerLength / SERFile.timestampSize, self.frameCount ) : 0

        if expectsTrailer, self.frameCount > 0, trailerLength == 0, options.contains( .allowMissingTrailer ) == false
        {
            throw SERError.invalidTrailerData( reason: "The header records a start date but the file carries no timestamp trailer" )
        }

        // A trailer too short to hold even one whole timestamp is still a
        // trailer, so it answers to the short-trailer flag rather than the
        // missing-trailer one.
        if expectsTrailer, trailerLength > 0, storedCount < self.frameCount, options.contains( .allowShortTrailer ) == false
        {
            throw SERError.invalidTrailerData( reason: "The timestamp trailer holds \( storedCount ) whole timestamps for \( self.frameCount ) frames" )
        }

        self.header              = header
        self.options             = options
        self.data                = data
        self.trailerOffset       = trailerOffset
        self.trailerCount        = storedCount
        self.hasTimestampTrailer = storedCount > 0
    }

    /// The widest offset from UTC any time zone uses, in ticks.
    ///
    /// World time zones run from UTC−12 to UTC+14, so a local reading is never
    /// more than fourteen hours away from the instant it describes.
    private static let maximumTimeZoneOffset = Int64( 14 * 3600 ) * SERTimestamp.ticksPerSecond

    /// The widest gap allowed between a capture's start and any timestamp in
    /// its trailer, in ticks.
    ///
    /// A SER file holds one video capture, whose frames are stamped from the
    /// moment the stream starts. Two days is far past any such capture, and
    /// still leaves room for the unknown time zone when only the local start
    /// time is on record. Frame data mistaken for a timestamp lands outside
    /// this window by centuries.
    private static let maximumTrailerSpan = Int64( 48 * 3600 ) * SERTimestamp.ticksPerSecond

    /// The earliest instant a timestamp in the trailer can name.
    ///
    /// The trailer is UTC, so the header's UTC start time is the exact bound
    /// when it records one. Falling back to the local start time means giving
    /// up ``maximumTimeZoneOffset``, since the zone the capture machine was in
    /// is unknown — a looser bound, but far better than none.
    ///
    /// - Parameters:
    ///   - local: The header's local start time.
    ///   - utc:   The header's UTC start time.
    /// - Returns: The earliest tick value a trailer entry may hold, or `nil`
    ///            when the header records no usable start time at all.
    private static func trailerAnchor( local: SERTimestamp, utc: SERTimestamp ) -> Int64?
    {
        if utc.ticks > 0
        {
            return utc.ticks
        }

        guard local.ticks > 0
        else
        {
            return nil
        }

        // Qualified, since conforming to `Sequence` brings a `max` of its own
        // into the type's scope.
        return Swift.max( 1, local.ticks - SERFile.maximumTimeZoneOffset )
    }

    /// The length, in timestamps, of the run of coherent timestamps a payload
    /// ends with.
    ///
    /// The trailer is whatever timestamps sit at the end of the file, so it is
    /// measured there rather than derived from the payload's length. Walking
    /// backwards from the last eight bytes, an entry belongs to the trailer
    /// while it names a representable instant, does not precede the entry
    /// before it, and falls within ``maximumTrailerSpan`` of the moment the
    /// capture started. Pixel data reached by walking past the trailer's start
    /// fails one of those almost at once — a frame of near-constant samples,
    /// the one shape that reads as a steady instant, misses the capture window
    /// by centuries — which is what makes the run's length the trailer's
    /// length.
    ///
    /// The one shape of frame data that passes all three is a stretch of bytes
    /// repeating a single pattern, which reads as the same instant over and
    /// over. A run of two or more that never advances is therefore rejected:
    /// several frames are not captured within the same 100 ns tick. The cost is
    /// that a trailer really stamped with one repeated instant — which a
    /// working capture does not produce — goes unrecognized in a file already
    /// corrupt enough to reach here.
    ///
    /// - Parameters:
    ///   - data:          The complete file contents.
    ///   - payloadLength: The number of bytes following the header.
    ///   - bytesPerFrame: The size of a single frame, which is never zero.
    ///   - notBefore:     The capture's UTC start, in ticks, when the header
    ///                    records a usable one.
    ///   - options:       The parsing options to apply.
    /// - Returns: The number of whole timestamps the payload ends with, never
    ///            more than the frames they could belong to.
    private static func trailerLength( of data: Data, payloadLength: Int, bytesPerFrame: Int, notBefore: Int64?, options: SERParsingOptions ) -> Int
    {
        // A frame size near `Int.max` leaves no room for a timestamp beside it,
        // so there is no run to look for. Only reachable where `Int` is 32 bits
        // wide.
        let ( frameCost, overflow ) = bytesPerFrame.addingReportingOverflow( SERFile.timestampSize )

        guard overflow == false
        else
        {
            return 0
        }

        // Every timestamp needs a frame to belong to, which bounds the walk.
        let limit = payloadLength / frameCost

        // Walked by hand rather than through a sequence operation: each step
        // has to stop the moment an entry fails, and compare against the entry
        // that followed it.
        var length   = 0
        var previous = Int64.max
        var last     = Int64.max

        while length < limit
        {
            let offset = SERHeader.size + payloadLength - ( ( length + 1 ) * SERFile.timestampSize )

            guard let raw = try? data.integer( Int64.self, at: offset, littleEndian: true )
            else
            {
                break
            }

            let timestamp = SERTimestamp( rawValue: raw, options: options )
            let earliest  = notBefore ?? 1
            let latest    = notBefore.map { $0 + SERFile.maximumTrailerSpan } ?? Int64.max

            guard timestamp.date != nil, timestamp.ticks <= previous, ( earliest ... latest ).contains( timestamp.ticks )
            else
            {
                break
            }

            if length == 0
            {
                last = timestamp.ticks
            }

            previous = timestamp.ticks
            length  += 1
        }

        // Several frames are never captured in the same 100 ns tick, so a run
        // that never advances is not a trailer — it is a stretch of pixels that
        // happen to repeat one byte pattern, which is otherwise the one shape
        // of frame data that satisfies every test above.
        return length > 1 && previous == last ? 0 : length
    }

    /// The number of whole frames a payload holds.
    ///
    /// This is only ever reached for a file that already contradicts its own
    /// header, so the count cannot be read and has to be established from the
    /// bytes. Splitting the payload by a divisor cannot do it: one length with
    /// two unknowns reads both as more frames and as fewer frames followed by
    /// their timestamps, and files exist that fit both readings exactly with
    /// different answers.
    ///
    /// Measuring the trailer where it actually is — at the end of the file —
    /// leaves only one unknown. The frames are then whatever precedes the run
    /// of timestamps found there, taking the longest run that divides the
    /// remaining bytes into whole frames and leaves at least one frame per
    /// timestamp. A capture cut off before its trailer was written has no such
    /// run and keeps every frame it managed to write.
    ///
    /// - Parameters:
    ///   - payloadLength: The number of bytes following the header.
    ///   - data:          The complete file contents.
    ///   - bytesPerFrame: The size of a single frame, which is never zero.
    ///   - withTrailer:   Whether the header records a start date, and so
    ///                    claims a trailer at all.
    ///   - notBefore:     The capture's UTC start, in ticks, when the header
    ///                    records a usable one.
    ///   - options:       The parsing options to apply.
    /// - Returns: The number of whole frames that fit.
    private static func frameCount( fittingIn payloadLength: Int, of data: Data, bytesPerFrame: Int, withTrailer: Bool, notBefore: Int64?, options: SERParsingOptions ) -> Int
    {
        guard withTrailer
        else
        {
            return payloadLength / bytesPerFrame
        }

        let run = SERFile.trailerLength( of: data, payloadLength: payloadLength, bytesPerFrame: bytesPerFrame, notBefore: notBefore, options: options )

        let timestamps = stride( from: run, through: 1, by: -1 ).first
        {
            let remaining = payloadLength - ( $0 * SERFile.timestampSize )

            return remaining % bytesPerFrame == 0 && $0 <= remaining / bytesPerFrame
        }

        return ( payloadLength - ( ( timestamps ?? 0 ) * SERFile.timestampSize ) ) / bytesPerFrame
    }

    /// The byte offset at which a frame's pixel data begins.
    ///
    /// - Parameter index: The frame's index, in `0 ..< frameCount`.
    /// - Returns: The offset, in bytes, from the start of the data the file was
    ///            parsed from, which is not necessarily index zero when that
    ///            data is a slice.
    /// - Throws: ``SERError/frameIndexOutOfRange(index:count:)`` if the index
    ///           falls outside the frames the file holds.
    public func byteOffset( ofFrame index: Int ) throws -> Int
    {
        guard index >= 0, index < self.frameCount
        else
        {
            throw SERError.frameIndexOutOfRange( index: index, count: self.frameCount )
        }

        // The whole payload was already checked to fit within the file, so a
        // single frame's offset cannot overflow.
        return SERHeader.size + index * self.header.bytesPerFrame
    }

    /// The file's frames, addressed on demand.
    ///
    /// A random-access collection of ``frameCount`` frames, which builds each
    /// one as it is asked for and reads no pixel data doing so.
    public var frames: SERFrames
    {
        SERFrames( file: self )
    }

    /// The frame at an index.
    ///
    /// Frames are views onto the file's bytes: this reads none of the pixel
    /// data, which is decoded only when ``SERFrame/samples`` is asked for.
    ///
    /// - Parameter index: The frame's index, in `0 ..< frameCount`.
    /// - Returns: The frame at that index.
    /// - Throws: ``SERError/frameIndexOutOfRange(index:count:)`` if the index
    ///           falls outside the frames the file holds.
    public func frame( at index: Int ) throws -> SERFrame
    {
        let offset = try self.byteOffset( ofFrame: index )

        // The one timestamp is read straight from the trailer rather than
        // through `timestamps`, which would parse the whole trailer — a capture
        // of a hundred thousand frames would pay for all of them to look at one.
        return SERFrame( index: index, header: self.header, timestamp: self.timestamp( ofFrame: index ), rawData: self.frameData( at: offset ) )
    }

    /// The bytes a frame occupies.
    ///
    /// The payload was measured against the frame count when the file was
    /// parsed, so a frame's bytes are always entirely present. The range is
    /// nonetheless walked with bounded index arithmetic rather than built
    /// directly, so that being a fact about the file is not something the
    /// slicing could trap on.
    ///
    /// - Parameter offset: The frame's offset, from the start of the data the
    ///                     file was parsed from.
    /// - Returns: The frame's bytes, as a slice sharing the file's storage.
    private func frameData( at offset: Int ) -> Data
    {
        let start = self.data.index( self.data.startIndex, offsetBy: offset,                    limitedBy: self.data.endIndex ) ?? self.data.endIndex
        let end   = self.data.index( start,                offsetBy: self.header.bytesPerFrame, limitedBy: self.data.endIndex ) ?? self.data.endIndex

        return self.data[ start ..< end ]
    }

    /// Reads the timestamp recorded for one frame.
    ///
    /// - Parameter index: The frame's index.
    /// - Returns: The instant the frame was captured, or `nil` when the trailer
    ///            does not reach that frame or the stored value names no valid
    ///            instant.
    private func timestamp( ofFrame index: Int ) -> Date?
    {
        guard index >= 0, index < self.trailerCount,
              let raw = try? self.data.integer( Int64.self, at: self.trailerOffset + ( index * SERFile.timestampSize ), littleEndian: true )
        else
        {
            return nil
        }

        return SERTimestamp( rawValue: raw, options: self.options ).date
    }

    /// Reads every timestamp the trailer holds.
    ///
    /// - Returns: One entry per frame, `nil` where the trailer does not reach
    ///            or the stored value names no valid instant.
    private func parseTimestamps() -> [ Date? ]
    {
        ( 0 ..< self.frameCount ).map { self.timestamp( ofFrame: $0 ) }
    }

    /// A multi-line, human-readable summary of the file.
    public var description: String
    {
        """
        SERFile
        {
            Frame Count:       \( self.frameCount )
            Declared Frames:   \( self.header.frameCount )
            Bytes Per Frame:   \( self.header.bytesPerFrame )
            Timestamp Trailer: \( self.hasTimestampTrailer ? "Yes" : "No" )
            Start Time:        \( self.startTime.map { "\( $0 )" } ?? "Unknown" )
            Start Time UTC:    \( self.startTimeUTC.map { "\( $0 )" } ?? "Unknown" )
        }
        """
    }
}

/// Iteration over a file's frames.
///
/// Conforming ``SERFile`` itself lets a capture be walked with `for frame in
/// file`, and gives it the whole of `Sequence`'s vocabulary, without asking a
/// caller to reach for ``SERFile/frames`` first.
///
/// - Note: The conformance brings `Sequence`'s own members into the type's
///   scope, where they take precedence over free functions of the same name.
///   Code inside ``SERFile`` calling `min` or `max` therefore has to say
///   `Swift.min` or `Swift.max`. The failure is a compile error, not a wrong
///   answer.
extension SERFile: Sequence
{
    /// An iterator over the file's frames, in frame order.
    ///
    /// - Returns: An iterator yielding each of ``frames`` in turn.
    public func makeIterator() -> IndexingIterator< SERFrames >
    {
        self.frames.makeIterator()
    }

    /// The number of frames the iteration yields, which is exact rather than an
    /// estimate.
    public var underestimatedCount: Int
    {
        self.frameCount
    }
}
