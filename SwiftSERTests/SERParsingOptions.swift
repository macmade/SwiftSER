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

struct Test_SERParsingOptions
{
    /// Every individual leniency flag, paired with its name for diagnostics.
    static let leniencyFlags: [ ( name: String, option: SERParsingOptions ) ] = [
        ( "allowInvalidFileID",        .allowInvalidFileID ),
        ( "allowNonPrintableStrings",  .allowNonPrintableStrings ),
        ( "allowFrameCountMismatch",   .allowFrameCountMismatch ),
        ( "allowMissingTrailer",       .allowMissingTrailer ),
        ( "allowShortTrailer",         .allowShortTrailer ),
        ( "allowUnknownColorID",       .allowUnknownColorID ),
        ( "allowOutOfRangePixelDepth", .allowOutOfRangePixelDepth ),
        ( "allowInvalidTimestamps",    .allowInvalidTimestamps ),
    ]

    @Test
    func rawValueRoundTrips() async throws
    {
        [ 0, 1, 42 ].forEach
        {
            #expect( SERParsingOptions( rawValue: $0 ).rawValue == $0 )
        }
    }

    @Test
    func strictAndLenientPresetsExist() async throws
    {
        // The two presets must be usable option-set values, round-tripping
        // through their raw bitmask like any other option set.
        let strict:  SERParsingOptions = .strict
        let lenient: SERParsingOptions = .lenient

        #expect( strict  == SERParsingOptions( rawValue: strict.rawValue ) )
        #expect( lenient == SERParsingOptions( rawValue: lenient.rawValue ) )
    }

    @Test
    func optionSetAlgebra() async throws
    {
        var options: SERParsingOptions = []

        options.formUnion( .allowMissingTrailer )

        #expect( options.contains( .allowMissingTrailer ) )
        #expect( options.contains( .allowShortTrailer ) == false )
    }

    @Test
    func flagsHaveDistinctBits() async throws
    {
        // Two flags sharing a bit would make one silently imply the other.
        let bits = Set( Self.leniencyFlags.map { $0.option.rawValue } )

        #expect( bits.count == Self.leniencyFlags.count )
        #expect( bits.contains( 0 ) == false )
    }

    @Test
    func strictEnablesNoLeniency() async throws
    {
        // Strict parsing rejects everything the specification forbids, so it
        // must carry none of the leniency flags.
        Self.leniencyFlags.forEach
        {
            #expect( SERParsingOptions.strict.contains( $0.option ) == false, "\( $0.name ) must not be part of the strict preset" )
        }
    }

    @Test
    func lenientEnablesEveryLeniency() async throws
    {
        // A flag missing from the lenient preset would be unreachable for a
        // caller simply asking for real-world-friendly parsing.
        Self.leniencyFlags.forEach
        {
            #expect( SERParsingOptions.lenient.contains( $0.option ), "\( $0.name ) must be part of the lenient preset" )
        }
    }
}
