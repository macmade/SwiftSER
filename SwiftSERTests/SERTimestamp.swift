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

struct Test_SERTimestamp
{
    /// The tick value of a known instant, and the instant it stands for.
    static let knownTicks = Int64( 635_000_000_000_000_000 )

    /// The ISO 8601 rendering of ``knownTicks``.
    static let knownDate = "2013-03-27T16:53:20Z"

    /// Parses an ISO 8601 timestamp, so the expected instants in this suite are
    /// derived independently of the code under test.
    ///
    /// - Parameter string: The timestamp to parse.
    /// - Returns: The instant it names.
    static func date( _ string: String ) throws -> Date
    {
        try #require( ISO8601DateFormatter().date( from: string ) )
    }

    @Test
    func epochOffsetMatchesTheDotNetEpoch() async throws
    {
        // 719162 days separate 0001-01-01 from 1970-01-01 in the proleptic
        // Gregorian calendar, at 10 million ticks per second.
        #expect( SERTimestamp.ticksPerSecond == 10_000_000 )
        #expect( SERTimestamp.unixEpochTicks == 719_162 * 86_400 * 10_000_000 )
    }

    @Test
    func theEpochTickValueIsTheUnixEpoch() async throws
    {
        let timestamp = SERTimestamp( rawValue: SERTimestamp.unixEpochTicks, options: .strict )

        #expect( timestamp.date == Date( timeIntervalSince1970: 0 ) )
    }

    @Test
    func convertsAKnownTickValue() async throws
    {
        let timestamp = SERTimestamp( rawValue: Self.knownTicks, options: .strict )
        let expected  = try Self.date( Self.knownDate )

        #expect( timestamp.date == expected )
    }

    @Test
    func keepsSubSecondPrecision() async throws
    {
        // A tick is 100 ns, so the fractional part must survive the conversion
        // rather than being truncated to whole seconds.
        let timestamp = SERTimestamp( rawValue: Self.knownTicks + 5_000_000, options: .strict )
        let expected  = try Self.date( Self.knownDate ).addingTimeInterval( 0.5 )

        let interval = try #require( timestamp.date?.timeIntervalSince( expected ) )

        #expect( abs( interval ) < 0.000_001 )
    }

    @Test
    func nonPositiveValuesHaveNoDate() async throws
    {
        // The specification says a value of zero or less is invalid.
        [ Int64( 0 ), -1, Int64.min ].forEach
        {
            #expect( SERTimestamp( rawValue: $0, options: .strict ).date == nil )
        }
    }

    @Test
    func maskingIsAppliedBeforeTheValidityCheck() async throws
    {
        // The flag exists precisely for values whose high bits make them read as
        // negative, so the mask has to come first or it could never help.
        let rescued = Int64( bitPattern: UInt64( Self.knownTicks ) | ( 1 << 63 ) )

        #expect( SERTimestamp( rawValue: 0,         options: .lenient ).date == nil )
        #expect( SERTimestamp( rawValue: Int64.min, options: .lenient ).date == nil )
        #expect( SERTimestamp( rawValue: rescued,   options: .lenient ).date != nil )
    }

    @Test
    func rejectsTicksBeyondTheDocumentedRange() async throws
    {
        // 3652059 days span 0001-01-01 through 9999-12-31, the range the
        // encoding documents.
        #expect( SERTimestamp.maxTicks == 3_652_059 * 86_400 * 10_000_000 - 1 )

        #expect( SERTimestamp( rawValue: SERTimestamp.maxTicks,     options: .strict ).date != nil )
        #expect( SERTimestamp( rawValue: SERTimestamp.maxTicks + 1, options: .strict ).date == nil )
        #expect( SERTimestamp( rawValue: Int64.max,                 options: .strict ).date == nil )
    }

    @Test
    func maskingCannotRescueAWhollyCorruptValue() async throws
    {
        // -1 masks to the largest 62-bit tick count, which lands in the year
        // 14614. The upper bound is what stops that being handed back as a
        // date, so masking first costs nothing.
        let timestamp = SERTimestamp( rawValue: -1, options: .lenient )

        #expect( timestamp.ticks == 0x3FFF_FFFF_FFFF_FFFF )
        #expect( timestamp.date  == nil )
    }

    @Test
    func preservesTheRawValue() async throws
    {
        // Masking must not destroy what the file holds.
        let raw       = Int64( bitPattern: UInt64( 635_000_000_000_000_000 ) | ( 1 << 63 ) )
        let timestamp = SERTimestamp( rawValue: raw, options: .lenient )

        #expect( timestamp.rawValue == raw )
        #expect( timestamp.ticks    != raw )
    }

    @Test
    func masksTheUndocumentedHighBitsWhenAllowed() async throws
    {
        // Only 62 of the 64 bits are meaningful; the two most significant ones
        // are undocumented, and a file setting them still names a valid instant.
        let expected = try Self.date( Self.knownDate )

        [ UInt64( 1 ) << 62, UInt64( 1 ) << 63, ( UInt64( 1 ) << 62 ) | ( UInt64( 1 ) << 63 ) ].forEach
        {
            let raw       = Int64( bitPattern: UInt64( Self.knownTicks ) | $0 )
            let timestamp = SERTimestamp( rawValue: raw, options: .lenient )

            #expect( timestamp.ticks == Self.knownTicks )
            #expect( timestamp.date  == expected )
        }
    }

    @Test
    func keepsTheHighBitsUnderStrictParsing() async throws
    {
        // Strict parsing takes the field at face value: the two high bits are
        // part of the number, so the value is no longer the instant it looks
        // like.
        let raw       = Int64( bitPattern: UInt64( Self.knownTicks ) | ( 1 << 63 ) )
        let timestamp = SERTimestamp( rawValue: raw, options: .strict )

        #expect( timestamp.ticks == raw )
        #expect( timestamp.date  == nil )
    }

    @Test
    func maskingIsGatedByItsOwnFlag() async throws
    {
        // Removing just the timestamp flag from the lenient preset must bring
        // back the unmasked reading.
        let raw     = Int64( bitPattern: UInt64( Self.knownTicks ) | ( 1 << 63 ) )
        let options = SERParsingOptions.lenient.subtracting( .allowInvalidTimestamps )

        #expect( SERTimestamp( rawValue: raw, options: options ).date == nil )
        #expect( SERTimestamp( rawValue: raw, options: .allowInvalidTimestamps ).date != nil )
    }

    @Test
    func describesItself() async throws
    {
        let valid   = SERTimestamp( rawValue: Self.knownTicks, options: .strict )
        let invalid = SERTimestamp( rawValue: 0, options: .strict )

        #expect( valid.description.contains( "2013" ) )
        #expect( invalid.description.isEmpty == false )
        #expect( invalid.description.contains( "0" ) )
    }
}
