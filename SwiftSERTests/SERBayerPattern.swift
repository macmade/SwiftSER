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

struct Test_SERBayerPattern
{
    /// Every Bayer pattern, with the four-letter code and 2×2 tile it names.
    static let patterns: [ ( pattern: SERBayerPattern, code: String, isCMY: Bool, tile: [ SERBayerPattern.Filter ] ) ] = [
        ( .rggb, "RGGB", false, [ .red,     .green,   .green,   .blue    ] ),
        ( .grbg, "GRBG", false, [ .green,   .red,     .blue,    .green   ] ),
        ( .gbrg, "GBRG", false, [ .green,   .blue,    .red,     .green   ] ),
        ( .bggr, "BGGR", false, [ .blue,    .green,   .green,   .red     ] ),
        ( .cyym, "CYYM", true,  [ .cyan,    .yellow,  .yellow,  .magenta ] ),
        ( .ycmy, "YCMY", true,  [ .yellow,  .cyan,    .magenta, .yellow  ] ),
        ( .ymcy, "YMCY", true,  [ .yellow,  .magenta, .cyan,    .yellow  ] ),
        ( .myyc, "MYYC", true,  [ .magenta, .yellow,  .yellow,  .cyan    ] ),
    ]

    @Test
    func tableCoversEveryPattern() async throws
    {
        // Every other test in this suite iterates the table, so a row dropped
        // from it would quietly take its coverage along.
        #expect( Self.patterns.map { $0.code } == [ "RGGB", "GRBG", "GBRG", "BGGR", "CYYM", "YCMY", "YMCY", "MYYC" ] )
    }

    @Test
    func filterNamesItself() async throws
    {
        // The names are public API, and the tile cross-check below only ever
        // looks at their first letter.
        #expect( SERBayerPattern.Filter.red.description     == "Red" )
        #expect( SERBayerPattern.Filter.green.description   == "Green" )
        #expect( SERBayerPattern.Filter.blue.description    == "Blue" )
        #expect( SERBayerPattern.Filter.cyan.description    == "Cyan" )
        #expect( SERBayerPattern.Filter.yellow.description  == "Yellow" )
        #expect( SERBayerPattern.Filter.magenta.description == "Magenta" )
    }

    @Test
    func descriptionGivesTheFourLetterCode() async throws
    {
        Self.patterns.forEach
        {
            #expect( $0.pattern.description == $0.code )
        }
    }

    @Test
    func isCMYSeparatesTheComplementaryPatterns() async throws
    {
        Self.patterns.forEach
        {
            #expect( $0.pattern.isCMY == $0.isCMY, "\( $0.code ) is misclassified" )
        }
    }

    @Test
    func tileDescribesTheTwoByTwoLayout() async throws
    {
        Self.patterns.forEach
        {
            #expect( $0.pattern.tile == $0.tile, "\( $0.code ) has the wrong tile" )
        }
    }

    @Test
    func everyTileHoldsFourFilters() async throws
    {
        Self.patterns.forEach
        {
            #expect( $0.pattern.tile.count == 4, "\( $0.code ) does not describe a 2x2 tile" )
        }
    }

    @Test
    func tileAgreesWithTheFourLetterCode() async throws
    {
        // The code is not decoration: read row-major, its letters name the tile's
        // filters. A tile disagreeing with its own code would silently rotate the
        // mosaic during debayering.
        Self.patterns.forEach
        {
            let initials = $0.pattern.tile.map { $0.description.prefix( 1 ) }.joined()

            #expect( initials == $0.code )
        }
    }

    @Test
    func twiceSampledFilterAppearsTwicePerTile() async throws
    {
        // Green in the RGB patterns and yellow in the CMY ones are sampled twice
        // per tile, which is what gives them their own interpolation kernel.
        Self.patterns.forEach
        {
            let twiceSampled: SERBayerPattern.Filter = $0.isCMY ? .yellow : .green
            let count                                = $0.pattern.tile.filter { $0 == twiceSampled }.count

            #expect( count == 2, "\( $0.code ) does not sample \( twiceSampled ) twice" )
        }
    }

    @Test
    func rgbAndCMYPatternsUseDisjointFilters() async throws
    {
        let additive:      Set< SERBayerPattern.Filter > = [ .red,  .green,  .blue    ]
        let complementary: Set< SERBayerPattern.Filter > = [ .cyan, .yellow, .magenta ]

        Self.patterns.forEach
        {
            let expected = $0.isCMY ? complementary : additive

            #expect( Set( $0.pattern.tile ).isSubset( of: expected ), "\( $0.code ) mixes additive and complementary filters" )
        }
    }
}
