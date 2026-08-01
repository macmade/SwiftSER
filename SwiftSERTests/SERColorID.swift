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

struct Test_SERColorID
{
    /// Every color ID the specification defines, with the properties it implies.
    static let known: [ ( rawValue: Int32, colorID: SERColorID, name: String, planes: Int, isBayer: Bool, pattern: SERBayerPattern? ) ] = [
        (   0, .mono,      "MONO",       1, false, nil    ),
        (   8, .bayerRGGB, "BAYER_RGGB", 1, true,  .rggb  ),
        (   9, .bayerGRBG, "BAYER_GRBG", 1, true,  .grbg  ),
        (  10, .bayerGBRG, "BAYER_GBRG", 1, true,  .gbrg  ),
        (  11, .bayerBGGR, "BAYER_BGGR", 1, true,  .bggr  ),
        (  16, .bayerCYYM, "BAYER_CYYM", 1, true,  .cyym  ),
        (  17, .bayerYCMY, "BAYER_YCMY", 1, true,  .ycmy  ),
        (  18, .bayerYMCY, "BAYER_YMCY", 1, true,  .ymcy  ),
        (  19, .bayerMYYC, "BAYER_MYYC", 1, true,  .myyc  ),
        ( 100, .rgb,       "RGB",        3, false, nil    ),
        ( 101, .bgr,       "BGR",        3, false, nil    ),
    ]

    @Test
    func tableCoversEveryIdentifierTheSpecificationDefines() async throws
    {
        // Every other test in this suite iterates the table, so a row dropped
        // from it would quietly take its coverage along.
        #expect( Self.known.map { $0.rawValue } == [ 0, 8, 9, 10, 11, 16, 17, 18, 19, 100, 101 ] )
    }

    @Test
    func rawValueRoundTrips() async throws
    {
        Self.known.forEach
        {
            #expect( SERColorID( rawValue: $0.rawValue ) == $0.colorID )
            #expect( $0.colorID.rawValue                 == $0.rawValue )
        }
    }

    @Test
    func numberOfPlanesFollowsTheSpecification() async throws
    {
        // MONO through BAYER_MYYC are single-plane mosaics; only RGB and BGR
        // carry three planes.
        Self.known.forEach
        {
            #expect( $0.colorID.numberOfPlanes == $0.planes, "\( $0.name ) declares the wrong number of planes" )
        }
    }

    @Test
    func isBayerIdentifiesTheMosaicPatterns() async throws
    {
        Self.known.forEach
        {
            #expect( $0.colorID.isBayer == $0.isBayer, "\( $0.name ) is misclassified" )
        }
    }

    @Test
    func bayerPatternMapsEveryMosaic() async throws
    {
        Self.known.forEach
        {
            #expect( $0.colorID.bayerPattern == $0.pattern, "\( $0.name ) maps to the wrong pattern" )
        }
    }

    @Test
    func descriptionUsesTheSpecificationNames() async throws
    {
        Self.known.forEach
        {
            #expect( $0.colorID.description == $0.name )
        }
    }

    @Test
    func unrecognizedValuesArePreserved() async throws
    {
        // A file carrying a color ID the specification does not define is still
        // readable under `allowUnknownColorID`, so the raw value must survive
        // the round trip rather than collapse onto a known case.
        [ Int32( 1 ), 7, 12, 20, 99, 102, -1, Int32.max, Int32.min ].forEach
        {
            let colorID = SERColorID( rawValue: $0 )

            #expect( colorID          == .unknown( $0 ) )
            #expect( colorID.rawValue == $0 )
        }
    }

    @Test
    func unrecognizedValuesAssumeASinglePlane() async throws
    {
        // Every defined single-plane ID outnumbers the two three-plane ones, and
        // an unknown ID gives nothing better to go on.
        let colorID = SERColorID( rawValue: 42 )

        #expect( colorID.numberOfPlanes == 1 )
        #expect( colorID.isBayer        == false )
        #expect( colorID.bayerPattern   == nil )
    }

    @Test
    func unrecognizedValuesDescribeThemselvesWithTheirRawValue() async throws
    {
        #expect( SERColorID( rawValue: 42 ).description.contains( "42" ) )
    }
}
