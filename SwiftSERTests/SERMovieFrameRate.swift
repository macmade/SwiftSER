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

import Foundation
@testable import SwiftSER
import Testing

struct Test_SERMovieFrameRate
{
    /// Both ways of naming a pace, with what each describes itself as.
    static let rates: [ ( rate: SERMovieFrameRate, description: String ) ] = [
        ( .constant( 30 ),                 "30.0 fps" ),
        ( .fromTimestamps( fallback: 25 ), "From timestamps, or 25.0 fps" ),
    ]

    @Test
    func tableCoversEveryPace() async throws
    {
        // The tests below iterate this table, so a row dropped from it would
        // leave them passing while proving less.
        #expect( Self.rates.map { $0.description } == [ "30.0 fps", "From timestamps, or 25.0 fps" ] )
    }

    @Test
    func describesItself() async throws
    {
        Self.rates.forEach
        {
            #expect( $0.rate.description == $0.description, "\( $0.rate ) describes itself wrongly" )
        }
    }

    @Test
    func theTwoPacesAreDistinct() async throws
    {
        // A constant rate and a fallback of the same value are different
        // instructions, not the same one written twice.
        #expect( SERMovieFrameRate.constant( 30 ) != SERMovieFrameRate.fromTimestamps( fallback: 30 ) )
        #expect( SERMovieFrameRate.constant( 30 ) == SERMovieFrameRate.constant( 30 ) )
        #expect( SERMovieFrameRate.constant( 30 ) != SERMovieFrameRate.constant( 25 ) )

        #expect( SERMovieFrameRate.fromTimestamps( fallback: 30 ) == SERMovieFrameRate.fromTimestamps( fallback: 30 ) )
        #expect( SERMovieFrameRate.fromTimestamps( fallback: 30 ) != SERMovieFrameRate.fromTimestamps( fallback: 25 ) )
    }
}

#endif
