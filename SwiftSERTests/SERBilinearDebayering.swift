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

struct Test_SERBilinearDebayering
{
    /// The eight patterns debayering a 2×2 mosaic of `1 2 / 3 4`, with the
    /// twelve interleaved RGB samples each produces.
    ///
    /// Hand-computed. A 2×2 mosaic holds exactly one tile, so each of the four
    /// sites carries a different filter — two of them the twice-sampled one —
    /// and the whole result follows from the two kernels with nothing to
    /// average over but the tile itself. A pattern wired to the wrong tile
    /// therefore cannot produce another pattern's answer.
    ///
    /// For the complementary patterns the values are what the transform
    /// produces after interpolation, including where it clamps at zero.
    static let singleTile: [ ( pattern: SERBayerPattern, rgb: [ Double ] ) ] = [
        (
            // R = 1, G = 2.5 / 2 / 3 / 2.5, B = 4
            .rggb,
            [
                1.0, 2.5, 4.0,
                1.0, 2.0, 4.0,
                1.0, 3.0, 4.0,
                1.0, 2.5, 4.0,
            ]
        ),
        (
            // R = 2, G = 1 / 2.5 / 2.5 / 4, B = 3
            .grbg,
            [
                2.0, 1.0, 3.0,
                2.0, 2.5, 3.0,
                2.0, 2.5, 3.0,
                2.0, 4.0, 3.0,
            ]
        ),
        (
            // R = 3, G = 1 / 2.5 / 2.5 / 4, B = 2
            .gbrg,
            [
                3.0, 1.0, 2.0,
                3.0, 2.5, 2.0,
                3.0, 2.5, 2.0,
                3.0, 4.0, 2.0,
            ]
        ),
        (
            // R = 4, G = 2.5 / 2 / 3 / 2.5, B = 1
            .bggr,
            [
                4.0, 2.5, 1.0,
                4.0, 2.0, 1.0,
                4.0, 3.0, 1.0,
                4.0, 2.5, 1.0,
            ]
        ),
        (
            // C = 1, Y = 2.5 / 2 / 3 / 2.5, M = 4
            .cyym,
            [
                2.75, 0.00, 1.25,
                2.50, 0.00, 1.50,
                3.00, 0.00, 1.00,
                2.75, 0.00, 1.25,
            ]
        ),
        (
            // C = 2, Y = 1 / 2.5 / 2.5 / 4, M = 3
            .ycmy,
            [
                1.00, 0.00, 2.00,
                1.75, 0.75, 1.25,
                1.75, 0.75, 1.25,
                2.50, 1.50, 0.50,
            ]
        ),
        (
            // C = 3, Y = 1 / 2.5 / 2.5 / 4, M = 2
            .ymcy,
            [
                0.00, 1.00, 2.00,
                0.75, 1.75, 1.25,
                0.75, 1.75, 1.25,
                1.50, 2.50, 0.50,
            ]
        ),
        (
            // C = 4, Y = 2.5 / 2 / 3 / 2.5, M = 1
            .myyc,
            [
                0.00, 2.75, 1.25,
                0.00, 2.50, 1.50,
                0.00, 3.00, 1.00,
                0.00, 2.75, 1.25,
            ]
        ),
    ]

    /// A 4×4 mosaic holding the values 1 through 16, row-major.
    ///
    /// Wide enough to have a genuine interior — the 2×2 block of sites that
    /// sees the whole 3×3 kernel — surrounded by a border ring that does not.
    static let fourByFour: [ Double ] = ( 1 ... 16 ).map { Double( $0 ) }

    /// What ``fourByFour`` debayers to under ``SERBayerPattern/rggb``.
    ///
    /// Hand-computed from the two kernels, one interpolated plane at a time:
    ///
    ///     R              G                       B
    ///      1  2  3  3     3.5   2     13/3  4    6  6  7  8
    ///      5  6  7  7     5     6     7     23/3 6  6  7  8
    ///      9 10 11 11     28/3 10    11    12   10 10 11 12
    ///      9 10 11 11    13    38/3  15    13.5 14 14 15 16
    ///
    /// The thirds are the border sites where the green kernel finds three of
    /// its four neighbours rather than four.
    static let fourByFourRGGB: [ Double ] = [
         1, 3.5,         6,   2,  2.0,         6,   3, 13.0 / 3.0,  7,   3,  4.0,          8,
         5, 5.0,         6,   6,  6.0,         6,   7,  7.0,        7,   7, 23.0 / 3.0,    8,
         9, 28.0 / 3.0, 10,  10, 10.0,        10,  11, 11.0,       11,  11, 12.0,         12,
         9, 13.0,       14,  10, 38.0 / 3.0,  14,  11, 15.0,       15,  11, 13.5,         16,
    ]

    /// The geometries the two convolution paths are compared over.
    ///
    /// The 1×1 through 2×2 entries have no interior at all, 3×3 has exactly one
    /// interior site, and the rest exercise the accelerated path properly —
    /// including one geometry of each parity, since the tile repeats every two
    /// pixels.
    static let geometries: [ ( width: Int, height: Int ) ] = [
        ( 1, 1 ), ( 2, 1 ), ( 1, 2 ), ( 2, 2 ), ( 3, 3 ), ( 4, 4 ), ( 5, 4 ), ( 4, 5 ), ( 7, 6 ), ( 9, 9 ),
    ]

    @Test
    func everyDebayeringTableIsListed() async throws
    {
        // The tests below iterate these tables, so a row dropped from one would
        // leave them passing while proving less.
        #expect( Self.singleTile.map { $0.pattern.description } == [ "RGGB", "GRBG", "GBRG", "BGGR", "CYYM", "YCMY", "YMCY", "MYYC" ] )
        #expect( Self.geometries.map { "\( $0.width )x\( $0.height )" } == [ "1x1", "2x1", "1x2", "2x2", "3x3", "4x4", "5x4", "4x5", "7x6", "9x9" ] )
        #expect( Self.fourByFour                                       == [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 ] )
    }

    // MARK: - The eight patterns

    @Test
    func debayersEveryPatternFromItsOwnTile() async throws
    {
        try Self.singleTile.forEach
        {
            let rgb = try SERBilinearDebayering().debayer( mosaic: [ 1, 2, 3, 4 ], width: 2, height: 2, pattern: $0.pattern )

            #expect( rgb == $0.rgb, "\( $0.pattern ) debayers to the wrong values" )
        }
    }

    @Test
    func debayersTheInteriorAndTheBorderOfAWiderMosaic() async throws
    {
        // The 4×4 case is where the kernels actually average: the two interior
        // rows and columns see the whole 3×3, the border ring does not, and the
        // expectation is hand-computed for both.
        let rgb = try SERBilinearDebayering().debayer( mosaic: Self.fourByFour, width: 4, height: 4, pattern: .rggb )

        #expect( rgb == Self.fourByFourRGGB )
    }

    @Test
    func aSampledSiteKeepsItsOwnValue() async throws
    {
        // Bilinear interpolation only fills in the samples a site does not
        // carry. Wherever the mosaic does hold the channel, the debayered value
        // is the stored one, unaveraged — including on the border, which is the
        // property a naive edge handling breaks first.
        let channels: [ SERBayerPattern.Filter: Int ] = [ .red: 0, .green: 1, .blue: 2 ]

        try Self.singleTile.filter { $0.pattern.isCMY == false }.forEach
        {
            let pattern = $0.pattern
            let rgb     = try SERBilinearDebayering().debayer( mosaic: Self.fourByFour, width: 4, height: 4, pattern: pattern )

            // Required before the subscripts below: a short result would
            // otherwise trap and take the whole run down with it, reporting
            // nothing for any other test.
            try #require( rgb.count == 4 * 4 * 3 )

            try ( 0 ..< 4 ).forEach
            {
                row in

                try ( 0 ..< 4 ).forEach
                {
                    column in

                    let filter  = pattern.tile[ ( row % 2 ) * 2 + ( column % 2 ) ]
                    let channel = try #require( channels[ filter ] )
                    let index   = row * 4 + column

                    #expect( rgb[ index * 3 + channel ] == Self.fourByFour[ index ], "\( pattern ) loses the stored \( filter ) at \( row ),\( column )" )
                }
            }
        }
    }

    @Test
    func aConstantMosaicStaysConstant() async throws
    {
        // Every kernel's weights sum to one over the sites it actually reaches,
        // so a flat field comes back flat — no darkened border, no seam between
        // the accelerated interior and the scalar ring. The complementary
        // transform maps a flat C = Y = M = v to R = G = B = v / 2.
        try Self.singleTile.forEach
        {
            let pattern  = $0.pattern
            let expected = pattern.isCMY ? 20.0 : 40.0

            try Self.geometries.forEach
            {
                let mosaic = [ Double ]( repeating: 40, count: $0.width * $0.height )
                let rgb    = try SERBilinearDebayering().debayer( mosaic: mosaic, width: $0.width, height: $0.height, pattern: pattern )

                #expect( rgb.count == mosaic.count * 3 )

                // A 1×1 or 2×1 mosaic does not hold every filter, and a channel
                // with no sample anywhere has nothing to interpolate from.
                guard $0.width >= 2, $0.height >= 2
                else
                {
                    return
                }

                #expect( rgb.allSatisfy { $0 == expected }, "\( pattern ) at \( $0.width )x\( $0.height ) is not flat" )
            }
        }
    }

    // MARK: - Geometry

    @Test
    func producesThreeSamplesPerPixel() async throws
    {
        try Self.geometries.forEach
        {
            let mosaic = ( 0 ..< $0.width * $0.height ).map { Double( $0 ) }
            let rgb    = try SERBilinearDebayering().debayer( mosaic: mosaic, width: $0.width, height: $0.height, pattern: .rggb )

            #expect( rgb.count == $0.width * $0.height * 3, "\( $0.width )x\( $0.height ) produces the wrong sample count" )
        }
    }

    @Test
    func aChannelWithNoSampleAtAllReadsZero() async throws
    {
        // A single-pixel mosaic holds one filter and nothing else. There is no
        // green and no blue to interpolate from, and inventing one would be
        // worse than reporting none.
        #expect( try SERBilinearDebayering().debayer( mosaic: [ 7 ], width: 1, height: 1, pattern: .rggb ) == [ 7, 0, 0 ] )
        #expect( try SERBilinearDebayering().debayer( mosaic: [ 7 ], width: 1, height: 1, pattern: .bggr ) == [ 0, 0, 7 ] )
    }

    @Test
    func debayersAMosaicOneSiteWide() async throws
    {
        // A single row or column still tiles, so the two filters it does carry
        // interpolate along it.
        #expect( try SERBilinearDebayering().debayer( mosaic: [ 1, 2 ], width: 2, height: 1, pattern: .rggb ) == [ 1, 2, 0, 1, 2, 0 ] )
        #expect( try SERBilinearDebayering().debayer( mosaic: [ 1, 2 ], width: 1, height: 2, pattern: .rggb ) == [ 1, 2, 0, 1, 2, 0 ] )
    }

    @Test
    func rejectsAMosaicThatDoesNotMatchTheGeometry() async throws
    {
        #expect( throws: SERError.self )
        {
            try SERBilinearDebayering().debayer( mosaic: [ 1, 2, 3 ], width: 2, height: 2, pattern: .rggb )
        }

        #expect( throws: SERError.self )
        {
            try SERBilinearDebayering().debayer( mosaic: [ 1, 2, 3, 4, 5 ], width: 2, height: 2, pattern: .rggb )
        }
    }

    @Test
    func rejectsAGeometryWithNoExtent() async throws
    {
        #expect( throws: SERError.self )
        {
            try SERBilinearDebayering().debayer( mosaic: [], width: 0, height: 2, pattern: .rggb )
        }

        #expect( throws: SERError.self )
        {
            try SERBilinearDebayering().debayer( mosaic: [], width: 2, height: 0, pattern: .rggb )
        }

        #expect( throws: SERError.self )
        {
            try SERBilinearDebayering().debayer( mosaic: [], width: -2, height: -2, pattern: .rggb )
        }
    }

    @Test
    func rejectsAGeometryThatOverflows() async throws
    {
        // No such mosaic can exist, but the size is computed before the mosaic
        // is looked at, so the multiplication has to be checked rather than
        // trusted.
        #expect( throws: SERError.self )
        {
            try SERBilinearDebayering().debayer( mosaic: [], width: Int.max, height: 2, pattern: .rggb )
        }
    }

    // MARK: - Delegation protocol

    @Test
    func supportsEveryPattern() async throws
    {
        // The built-in implementation is the library's safety net, so it never
        // declines: whatever a consumer's implementation refuses, this one
        // answers for.
        Self.singleTile.forEach
        {
            #expect( SERBilinearDebayering().supports( pattern: $0.pattern ), "\( $0.pattern ) is declined" )
        }
    }

    @Test
    func describesItself() async throws
    {
        #expect( SERBilinearDebayering().description == "Bilinear debayering" )
    }

    // MARK: - Convolution paths

    @Test
    func bothConvolutionPathsAgree() async throws
    {
        // The two implementations divide the work differently: the accelerated
        // one convolves the interior through Accelerate and leaves the border
        // ring to the scalar routine, the plain one computes every site. Both
        // arrive at the same values, exactly — samples are whole numbers and
        // the kernel weights are exact binary fractions, so no sum here depends
        // on the order it was accumulated in.
        try Self.singleTile.forEach
        {
            let pattern = $0.pattern

            try Self.geometries.forEach
            {
                let mosaic      = ( 0 ..< $0.width * $0.height ).map { Double( ( $0 * 37 ) % 65536 ) }
                let accelerated = try SERBilinearDebayering().debayer( mosaic: mosaic, width: $0.width, height: $0.height, pattern: pattern, accelerated: true )
                let scalar      = try SERBilinearDebayering().debayer( mosaic: mosaic, width: $0.width, height: $0.height, pattern: pattern, accelerated: false )

                #expect( accelerated == scalar, "\( pattern ) at \( $0.width )x\( $0.height ) differs between the two paths" )
            }
        }
    }

    @Test
    func theScalarPathMatchesTheHandComputedValues() async throws
    {
        // The public entry point takes the accelerated path, so the
        // hand-computed expectations above pin that one. This pins the other
        // against the same values, rather than only against its counterpart.
        let rgb = try SERBilinearDebayering().debayer( mosaic: Self.fourByFour, width: 4, height: 4, pattern: .rggb, accelerated: false )

        #expect( rgb == Self.fourByFourRGGB )
    }
}
