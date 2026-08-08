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

struct Test_SERMovieCodec
{
    /// Every codec, with the AVFoundation type it names, its common name and
    /// whether it preserves an odd frame dimension.
    static let codecs: [ ( codec: SERMovieCodec, type: AVVideoCodecType, name: String, keepsOddSize: Bool ) ] = [
        ( .h264,       .h264,       "H.264",       false ),
        ( .hevc,       .hevc,       "HEVC",        false ),
        ( .proRes422,  .proRes422,  "ProRes 422",  true  ),
        ( .proRes4444, .proRes4444, "ProRes 4444", true  ),
    ]

    @Test
    func tableCoversEveryCodec() async throws
    {
        // The tests below iterate this table, so a row dropped from it would
        // leave them passing while proving less. Asserted against `allCases`,
        // so a codec added later cannot go untested either.
        #expect( Self.codecs.map { $0.codec } == SERMovieCodec.allCases )
        #expect( Self.codecs.map { $0.name }  == [ "H.264", "HEVC", "ProRes 422", "ProRes 4444" ] )
    }

    @Test
    func namesTheMatchingAVFoundationCodec() async throws
    {
        Self.codecs.forEach
        {
            #expect( $0.codec.videoCodecType == $0.type, "\( $0.codec ) names the wrong AVFoundation codec" )
        }
    }

    @Test
    func describesItselfByItsCommonName() async throws
    {
        Self.codecs.forEach
        {
            #expect( $0.codec.description == $0.name, "\( $0.type.rawValue ) describes itself wrongly" )
        }
    }

    @Test
    func reportsWhetherItPreservesAnOddDimension() async throws
    {
        // The macroblock codecs round an odd dimension down; ProRes does not.
        Self.codecs.forEach
        {
            #expect( $0.codec.preservesOddDimensions == $0.keepsOddSize, "\( $0.codec ) misreports its handling of odd dimensions" )
        }
    }

    @Test
    func codecsAreDistinct() async throws
    {
        #expect( Set( Self.codecs.map { $0.type.rawValue } ).count == Self.codecs.count )
    }
}

#endif
