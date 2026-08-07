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

/// One of the 64-bit instants a SER file records, in the header's start-time
/// fields and in the per-frame timestamp trailer.
///
/// The value counts 100 ns ticks since 0001-01-01 00:00:00 in the proleptic
/// Gregorian calendar, which is how .NET's `DateTime` is encoded — the format
/// records what the capture software's runtime handed it. Only the low 62 bits
/// are meaningful; the two most significant ones are undocumented, so
/// ``SERParsingOptions/allowInvalidTimestamps`` masks them off rather than
/// letting them turn the instant into a nonsense far-future date or a negative
/// number.
public struct SERTimestamp: Sendable, Hashable, CustomStringConvertible
{
    /// The number of ticks in a second. A tick is 100 ns.
    public static let ticksPerSecond: Int64 = 10_000_000

    /// The tick value of the Unix epoch, 1970-01-01 00:00:00 UTC.
    ///
    /// 719162 days separate 0001-01-01 from 1970-01-01 in the proleptic
    /// Gregorian calendar: `719162 × 86400 × 10000000`.
    public static let unixEpochTicks: Int64 = 621_355_968_000_000_000

    /// The largest tick value that names a representable instant, the last tick
    /// of 9999-12-31.
    ///
    /// The specification quotes the encoding's documented range as "dates
    /// ranging from January 1 of the year 0001 through December 31 of the year
    /// 9999". 3652059 days span that range:
    /// `3652059 × 86400 × 10000000 - 1`.
    public static let maxTicks: Int64 = 3_155_378_975_999_999_999

    /// The mask covering the 62 meaningful bits of a stored tick value.
    private static let meaningfulBits: UInt64 = 0x3FFF_FFFF_FFFF_FFFF

    /// The tick value exactly as the file stores it.
    public let rawValue: Int64

    /// The tick value the instant is read from.
    ///
    /// The same as ``rawValue``, unless
    /// ``SERParsingOptions/allowInvalidTimestamps`` was set, in which case the
    /// two undocumented high bits have been cleared.
    public let ticks: Int64

    /// The instant the value names, or `nil` when it names none.
    ///
    /// The value must fall in `1 ... maxTicks`: the specification states that
    /// zero or less is invalid, and anything past ``maxTicks`` is outside the
    /// range the encoding documents. Both bounds are tested against ``ticks``
    /// rather than ``rawValue``, since masking has to come first — the values
    /// it exists to rescue are exactly those whose high bits make them read as
    /// negative. The upper bound is what keeps that ordering safe: a wholly
    /// corrupt `-1` masks to the largest 62-bit tick count, which lands in the
    /// year 14614 and is rejected here rather than handed back as a date.
    ///
    /// The conversion is exact in whole seconds and carries the sub-second
    /// remainder separately, so it is limited only by `Date`'s own
    /// floating-point resolution.
    public var date: Date?
    {
        guard ( 1 ... SERTimestamp.maxTicks ).contains( self.ticks )
        else
        {
            return nil
        }

        // Splitting the division keeps the seconds exact instead of rounding
        // the whole tick count through a `Double`.
        let delta     = self.ticks - SERTimestamp.unixEpochTicks
        let seconds   = delta / SERTimestamp.ticksPerSecond
        let remainder = delta % SERTimestamp.ticksPerSecond

        return Date( timeIntervalSince1970: Double( seconds ) + Double( remainder ) / Double( SERTimestamp.ticksPerSecond ) )
    }

    /// Creates a timestamp from a stored tick value.
    ///
    /// - Parameters:
    ///   - rawValue: The 64-bit tick count, as stored in the file.
    ///   - options:  The parsing options to apply.
    public init( rawValue: Int64, options: SERParsingOptions )
    {
        self.rawValue = rawValue
        self.ticks    = options.contains( .allowInvalidTimestamps ) ? Int64( bitPattern: UInt64( bitPattern: rawValue ) & SERTimestamp.meaningfulBits ) : rawValue
    }

    /// The instant the value names, or a note that it names none.
    public var description: String
    {
        guard let date = self.date
        else
        {
            return "Invalid timestamp (\( self.rawValue ))"
        }

        return "\( date )"
    }
}
