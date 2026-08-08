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

struct Test_SERMovieExportOptions
{
    @Test
    func keepsWhatItWasGiven() async throws
    {
        let options = SERMovieExportOptions( codec: .proRes422, frameRate: .constant( 24 ), scaled: false )

        #expect( options.codec     == .proRes422 )
        #expect( options.frameRate == .constant( 24 ) )
        #expect( options.scaled    == false )
    }

    @Test
    func describesEveryOption() async throws
    {
        let scaled   = SERMovieExportOptions( codec: .hevc, frameRate: .constant( 30 ), scaled: true )
        let unscaled = SERMovieExportOptions( codec: .h264, frameRate: .fromTimestamps( fallback: 25 ), scaled: false )

        #expect( scaled.description   == "HEVC, 30.0 fps, scaled" )
        #expect( unscaled.description == "H.264, From timestamps, or 25.0 fps" )
    }

    @Test
    func optionsThatDifferAreNotEqual() async throws
    {
        let base = SERMovieExportOptions( codec: .h264, frameRate: .constant( 30 ), scaled: true )

        #expect( base == SERMovieExportOptions( codec: .h264, frameRate: .constant( 30 ), scaled: true ) )
        #expect( base != SERMovieExportOptions( codec: .hevc, frameRate: .constant( 30 ), scaled: true ) )
        #expect( base != SERMovieExportOptions( codec: .h264, frameRate: .constant( 25 ), scaled: true ) )
        #expect( base != SERMovieExportOptions( codec: .h264, frameRate: .constant( 30 ), scaled: false ) )
    }
}

#endif
