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

#if canImport( Accelerate )
import Accelerate
#endif

/// SwiftSER's own debayering: bilinear interpolation over all eight patterns.
///
/// Bilinear demosaicing is one 3×3 convolution per channel. Each channel is
/// masked out of the mosaic — every site the pattern gives that filter keeps its
/// sample, the rest read zero — and convolving what remains with the kernel
/// below fills in what a site did not sample:
///
///     Red / blue,             Green / yellow,
///     cyan / magenta          sampled twice
///     sampled once per tile   per tile
///
///     1/4 * [ 1 2 1 ]         1/4 * [ 0 1 0 ]
///           [ 2 4 2 ]               [ 1 4 1 ]
///           [ 1 2 1 ]               [ 0 1 0 ]
///
/// The weights are chosen so that they sum to one over the sites of that channel
/// a full 3×3 neighbourhood contains, whatever the site's position within the
/// tile. A site at the image's edge does not have a full neighbourhood, so there
/// the weights are summed as they are applied and the result divided by what was
/// actually found — the same average, over the samples that exist. A channel
/// with no sample anywhere in reach, which a mosaic less than two pixels wide or
/// two pixels high produces, reads zero.
///
/// - Note: This implementation never declines a pattern, which is what makes it
///         usable as the fallback behind any ``SERDebayering`` a consumer
///         installs.
///
/// - Important: The four complementary patterns — ``SERBayerPattern/cyym``,
///              ``SERBayerPattern/ycmy``, ``SERBayerPattern/ymcy`` and
///              ``SERBayerPattern/myyc`` — are interpolated the same way and
///              then converted to RGB by the ideal complementary transform. It
///              assumes filters that do not overlap, which no real sensor has.
///              The format records no calibration matrix and the specification
///              defines no transform, so colors from those four patterns are
///              plausible but not colorimetrically accurate.
public struct SERBilinearDebayering: SERDebayering, Sendable, CustomStringConvertible
{
    /// The number of planes debayering produces, which is RGB's three.
    internal static let planeCount = 3

    /// The 3×3 kernel of a filter the tile samples once.
    ///
    /// Row-major, weights already divided by four. Red, blue, cyan and magenta
    /// take this one: a site of theirs sits at one corner of the tile, so the
    /// neighbouring samples are two away horizontally, vertically or both.
    private static let singleSiteKernel: [ Double ] = [
        0.25, 0.50, 0.25,
        0.50, 1.00, 0.50,
        0.25, 0.50, 0.25,
    ]

    /// The 3×3 kernel of a filter the tile samples twice.
    ///
    /// Row-major, weights already divided by four. Green and yellow take this
    /// one: their two sites per tile are diagonally opposite, so from any site
    /// that is not one of theirs the nearest are the four sites adjacent to it,
    /// and the diagonals are never theirs.
    private static let doubleSiteKernel: [ Double ] = [
        0.00, 0.25, 0.00,
        0.25, 1.00, 0.25,
        0.00, 0.25, 0.00,
    ]

    /// Creates the built-in debayering implementation.
    ///
    /// It holds no state, so one is as good as another.
    public init()
    {}

    /// Whether this implementation handles the given pattern, which it always
    /// does.
    ///
    /// - Parameter pattern: The mosaic laid over the sensor.
    /// - Returns: `true`, for every pattern.
    public func supports( pattern: SERBayerPattern ) -> Bool
    {
        true
    }

    /// Debayers one frame's mosaic.
    ///
    /// - Parameters:
    ///   - mosaic:  The frame's samples: single-plane, row-major and
    ///              non-normalized, holding `width * height` values. Assumed
    ///              non-negative and finite, as ``SERFrame/samples`` guarantees.
    ///              The complementary patterns' transform clamps its result at
    ///              zero, so it would discard genuinely signed input and turn a
    ///              NaN — which `max` swallows — into one.
    ///   - width:   The image's width, in pixels.
    ///   - height:  The image's height, in pixels.
    ///   - pattern: The mosaic laid over the sensor.
    /// - Returns: Interleaved RGB, row-major, holding `width * height * 3`
    ///            values.
    /// - Throws: ``SERError/debayerError(reason:)`` if the geometry has no
    ///           extent, if it overflows, or if `mosaic` does not hold exactly
    ///           one sample per pixel.
    public func debayer( mosaic: [ Double ], width: Int, height: Int, pattern: SERBayerPattern ) throws -> [ Double ]
    {
        try self.debayer( mosaic: mosaic, width: width, height: height, pattern: pattern, accelerated: true )
    }

    /// Debayers one frame's mosaic through a chosen convolution implementation.
    ///
    /// Both implementations are always compiled, so the plain-Swift one does not
    /// go untested wherever Accelerate happens to be available.
    /// ``debayer(mosaic:width:height:pattern:)`` asks for the accelerated one,
    /// which falls back on its own when the platform offers no Accelerate.
    ///
    /// - Parameters:
    ///   - mosaic:      The frame's samples, holding `width * height` values.
    ///   - width:       The image's width, in pixels.
    ///   - height:      The image's height, in pixels.
    ///   - pattern:     The mosaic laid over the sensor.
    ///   - accelerated: Whether to convolve through Accelerate when the platform
    ///                  provides it.
    /// - Returns: Interleaved RGB, row-major, holding `width * height * 3`
    ///            values.
    /// - Throws: ``SERError/debayerError(reason:)`` if the geometry has no
    ///           extent, if it overflows, or if `mosaic` does not hold exactly
    ///           one sample per pixel.
    internal func debayer( mosaic: [ Double ], width: Int, height: Int, pattern: SERBayerPattern, accelerated: Bool ) throws -> [ Double ]
    {
        guard width > 0, height > 0
        else
        {
            throw SERError.debayerError( reason: "Invalid image geometry: \( width )x\( height )" )
        }

        let ( sampleCount, sampleOverflow ) = width.multipliedReportingOverflow( by: height )

        guard sampleOverflow == false
        else
        {
            throw SERError.debayerError( reason: "Image geometry overflows: \( width )x\( height )" )
        }

        guard mosaic.count == sampleCount
        else
        {
            throw SERError.debayerError( reason: "A \( width )x\( height ) mosaic holds \( sampleCount ) samples, found \( mosaic.count )" )
        }

        let ( outputCount, outputOverflow ) = sampleCount.multipliedReportingOverflow( by: SERBilinearDebayering.planeCount )

        guard outputOverflow == false
        else
        {
            throw SERError.debayerError( reason: "A \( width )x\( height ) image of \( SERBilinearDebayering.planeCount ) planes overflows" )
        }

        var samples = [ Double ]( repeating: 0, count: outputCount )
        var plane   = [ Double ]( repeating: 0, count: sampleCount )

        // One plane buffer serves all three channels, scattered into the
        // interleaved result as each is finished. What the debayering costs in
        // memory beyond its own result is therefore that one plane, plus — on
        // the accelerated path alone — a masked copy of the mosaic that lives no
        // longer than the convolution itself.
        SERBilinearDebayering.filters( of: pattern ).enumerated().forEach
        {
            let channel = $0.offset

            SERBilinearDebayering.interpolate( $0.element, from: mosaic, width: width, height: height, pattern: pattern, accelerated: accelerated, into: &plane )

            // Scattering a contiguous plane into every third slot, by index:
            // this is a per-pixel loop. There is no accelerated counterpart to
            // select between here, since none of Accelerate's strided copies
            // beats it — its submatrix move is markedly slower at one column,
            // and a multiply by one only matches.
            plane.indices.forEach
            {
                samples[ $0 * SERBilinearDebayering.planeCount + channel ] = plane[ $0 ]
            }
        }

        if pattern.isCMY
        {
            SERBilinearDebayering.convertToRGB( &samples )
        }

        return samples
    }

    /// The three filters a pattern is interpolated into, in the order they are
    /// interleaved.
    ///
    /// - Parameter pattern: The mosaic laid over the sensor.
    /// - Returns: Red, green and blue for the additive patterns; cyan, yellow
    ///            and magenta for the complementary ones, which
    ///            ``convertToRGB(_:)`` then turns into the additive primaries.
    private static func filters( of pattern: SERBayerPattern ) -> [ SERBayerPattern.Filter ]
    {
        pattern.isCMY ? [ .cyan, .yellow, .magenta ] : [ .red, .green, .blue ]
    }

    /// Interpolates one channel over the whole image.
    ///
    /// Every site of `plane` is written, whichever path runs, so the same buffer
    /// can serve one channel after another.
    ///
    /// - Parameters:
    ///   - filter:      The channel to interpolate.
    ///   - mosaic:      The frame's samples, holding `width * height` values.
    ///   - width:       The image's width, in pixels.
    ///   - height:      The image's height, in pixels.
    ///   - pattern:     The mosaic laid over the sensor.
    ///   - accelerated: Whether to convolve through Accelerate when the platform
    ///                  provides it.
    ///   - plane:       The buffer to write the channel into, one value per
    ///                  pixel, row-major.
    private static func interpolate( _ filter: SERBayerPattern.Filter, from mosaic: [ Double ], width: Int, height: Int, pattern: SERBayerPattern, accelerated: Bool, into plane: inout [ Double ] )
    {
        // Every filter of every pattern occupies one tile position or two —
        // never none, three or four — which is what makes the two kernels a
        // complete choice.
        let tileHoldsFilter = pattern.tile.map { $0 == filter }
        let kernel          = tileHoldsFilter.filter { $0 }.count == 2 ? SERBilinearDebayering.doubleSiteKernel : SERBilinearDebayering.singleSiteKernel

        // The convolution fills the interior and zeroes the one-pixel border
        // ring it cannot reach. What it fills needs no further work: an interior
        // site sees the kernel's full weight, which is one. The ring is left to
        // the scalar routine, which is where it belongs anyway, since a site
        // missing part of its neighbourhood has to divide by the weight it
        // really found.
        let convolved = accelerated && SERBilinearDebayering.convolveInterior( of: mosaic, width: width, height: height, kernel: kernel, tileHoldsFilter: tileHoldsFilter, into: &plane )

        SERBilinearDebayering.fill( &plane, from: mosaic, width: width, height: height, kernel: kernel, tileHoldsFilter: tileHoldsFilter, borderOnly: convolved )
    }

    /// Convolves one channel's interior through Accelerate.
    ///
    /// The masked copy the convolution reads is built here rather than by the
    /// caller, so it exists only where it is used: the scalar routine consults
    /// the pattern itself and reads the mosaic directly.
    ///
    /// - Parameters:
    ///   - mosaic:          The frame's samples, holding `width * height`
    ///                      values.
    ///   - width:           The image's width, in pixels.
    ///   - height:          The image's height, in pixels.
    ///   - kernel:          The channel's 3×3 kernel, row-major.
    ///   - tileHoldsFilter: Whether each of the tile's four positions carries
    ///                      the channel, row-major.
    ///   - plane:           The buffer to write the interior into.
    /// - Returns: Whether the convolution ran, which it does not below 3×3 or
    ///            where the platform provides no Accelerate.
    private static func convolveInterior( of mosaic: [ Double ], width: Int, height: Int, kernel: [ Double ], tileHoldsFilter: [ Bool ], into plane: inout [ Double ] ) -> Bool
    {
        // `vDSP_f3x3D` writes only the sites whose whole 3×3 neighbourhood lies
        // inside the image, and zeroes the one-pixel border around them, so
        // there is nothing at all for it to do below 3×3.
        guard width >= 3, height >= 3
        else
        {
            return false
        }

        #if canImport( Accelerate )
        // A scratch buffer rather than an array: the masked mosaic exists only
        // for the length of this call, and runs to the frame's whole sample
        // count in doubles.
        return withUnsafeTemporaryAllocation( of: Double.self, capacity: mosaic.count )
        {
            masked in

            SERBilinearDebayering.mask( mosaic, into: masked, width: width, height: height, tileHoldsFilter: tileHoldsFilter )

            return kernel.withUnsafeBufferPointer
            {
                filter in

                plane.withUnsafeMutableBufferPointer
                {
                    output in

                    guard let input = masked.baseAddress, let filter = filter.baseAddress, let output = output.baseAddress
                    else
                    {
                        return false
                    }

                    // `vDSP_f3x3D` correlates rather than convolves — it applies
                    // the kernel unflipped — which comes to the same thing here
                    // and in `interpolated(from:row:column:...)` only because
                    // both kernels are symmetric under a half turn.
                    vDSP_f3x3D( input, vDSP_Length( height ), vDSP_Length( width ), filter, output )

                    return true
                }
            }
        }
        #else
        return false
        #endif
    }

    /// Masks one channel out of the mosaic.
    ///
    /// - Parameters:
    ///   - mosaic:          The frame's samples, holding `width * height`
    ///                      values.
    ///   - masked:          The buffer to fill, whose length is the mosaic's.
    ///                      It arrives uninitialized, so every element is
    ///                      initialized rather than assigned to.
    ///   - width:           The image's width, in pixels.
    ///   - height:          The image's height, in pixels.
    ///   - tileHoldsFilter: Whether each of the tile's four positions carries
    ///                      the channel, row-major.
    private static func mask( _ mosaic: [ Double ], into masked: UnsafeMutableBufferPointer< Double >, width: Int, height: Int, tileHoldsFilter: [ Bool ] )
    {
        // Written by index rather than transformed from the mosaic: this is a
        // per-pixel loop, and what a site contributes depends on its position
        // within the repeating 2×2 tile rather than on the sample itself.
        ( 0 ..< height ).forEach
        {
            row in

            let rowOffset = row * width
            let tileRow   = ( row % 2 ) * 2

            ( 0 ..< width ).forEach
            {
                column in

                let index = rowOffset + column

                masked.initializeElement( at: index, to: tileHoldsFilter[ tileRow + ( column % 2 ) ] ? mosaic[ index ] : 0 )
            }
        }
    }

    /// Fills a plane's sites through the plain-Swift convolution.
    ///
    /// - Parameters:
    ///   - plane:           The plane to write into.
    ///   - mosaic:          The frame's samples, holding `width * height`
    ///                      values.
    ///   - width:           The image's width, in pixels.
    ///   - height:          The image's height, in pixels.
    ///   - kernel:          The channel's 3×3 kernel, row-major.
    ///   - tileHoldsFilter: Whether each of the tile's four positions carries
    ///                      the channel, row-major.
    ///   - borderOnly:      Whether to fill only the one-pixel border ring,
    ///                      which is what the accelerated convolution leaves
    ///                      behind.
    private static func fill( _ plane: inout [ Double ], from mosaic: [ Double ], width: Int, height: Int, kernel: [ Double ], tileHoldsFilter: [ Bool ], borderOnly: Bool )
    {
        ( 0 ..< height ).forEach
        {
            row in

            // A border row is filled entire. On a row between them only the
            // first and last sites are left, which is what striding by one less
            // than the width visits.
            let isBorderRow = row == 0 || row == height - 1
            let step        = borderOnly && isBorderRow == false ? max( 1, width - 1 ) : 1

            stride( from: 0, to: width, by: step ).forEach
            {
                column in

                plane[ row * width + column ] = SERBilinearDebayering.interpolated( from: mosaic, row: row, column: column, width: width, height: height, kernel: kernel, tileHoldsFilter: tileHoldsFilter )
            }
        }
    }

    /// Interpolates one channel at one site.
    ///
    /// Reads the mosaic rather than a masked copy of it, since a neighbour whose
    /// position in the tile carries a different filter is skipped here anyway.
    ///
    /// - Parameters:
    ///   - mosaic:          The frame's samples, holding `width * height`
    ///                      values.
    ///   - row:             The site's row.
    ///   - column:          The site's column.
    ///   - width:           The image's width, in pixels.
    ///   - height:          The image's height, in pixels.
    ///   - kernel:          The channel's 3×3 kernel, row-major.
    ///   - tileHoldsFilter: Whether each of the tile's four positions carries
    ///                      the channel, row-major.
    /// - Returns: The channel's value at the site, or zero when no sample of it
    ///            lies within reach.
    private static func interpolated( from mosaic: [ Double ], row: Int, column: Int, width: Int, height: Int, kernel: [ Double ], tileHoldsFilter: [ Bool ] ) -> Double
    {
        var sum    = 0.0
        var weight = 0.0

        // The per-site inner loop, walked by index over the 3×3 neighbourhood.
        // A neighbour outside the image is skipped rather than replaced by
        // something else, and one whose position in the tile carries a different
        // filter holds no sample of this channel. Summing the weights as they
        // are applied is what lets a site short of neighbours still average
        // correctly: a site with the whole neighbourhood always finds exactly
        // one, which is why the accelerated convolution needs no such division.
        ( -1 ... 1 ).forEach
        {
            rowOffset in

            let neighbourRow = row + rowOffset

            guard neighbourRow >= 0, neighbourRow < height
            else
            {
                return
            }

            ( -1 ... 1 ).forEach
            {
                columnOffset in

                let neighbourColumn = column + columnOffset

                guard neighbourColumn >= 0, neighbourColumn < width, tileHoldsFilter[ ( neighbourRow % 2 ) * 2 + ( neighbourColumn % 2 ) ]
                else
                {
                    return
                }

                let factor = kernel[ ( rowOffset + 1 ) * 3 + ( columnOffset + 1 ) ]

                sum    += mosaic[ neighbourRow * width + neighbourColumn ] * factor
                weight += factor
            }
        }

        return weight > 0 ? sum / weight : 0
    }

    /// Converts interleaved cyan/yellow/magenta samples to RGB, in place.
    ///
    /// The complementary filters pass the two additive primaries they are not
    /// the complement of — `C = G + B`, `Y = R + G`, `M = R + B` — and solving
    /// that system for the primaries gives the transform applied here. It is an
    /// approximation: real complementary sensors have substantial spectral
    /// overlap, and the format records nothing to correct for it with.
    ///
    /// - Parameter samples: The interpolated planes, three per pixel, cyan
    ///                      first. Left red first.
    private static func convertToRGB( _ samples: inout [ Double ] )
    {
        // Three samples at a time. The bound leaves out any trailing partial
        // pixel, which a three-plane buffer never has.
        stride( from: 0, to: samples.count - ( samples.count % SERBilinearDebayering.planeCount ), by: SERBilinearDebayering.planeCount ).forEach
        {
            let cyan    = samples[ $0 ]
            let yellow  = samples[ $0 + 1 ]
            let magenta = samples[ $0 + 2 ]

            // Only the lower bound needs clamping, and only because the mosaic's
            // samples are unsigned — which is what ``SERFrame/samples`` decodes
            // them as. Each interpolated value is then a weighted average of
            // non-negative samples, so none of the three exceeds the largest
            // sample the frame holds, and no half-sum of two of them less a
            // third can either. Subtracting can take a noisy pixel below zero,
            // which is not a color.
            samples[ $0 ]     = max( 0, ( yellow + magenta - cyan    ) / 2 )
            samples[ $0 + 1 ] = max( 0, ( cyan   + yellow  - magenta ) / 2 )
            samples[ $0 + 2 ] = max( 0, ( cyan   + magenta - yellow  ) / 2 )
        }
    }

    /// A human-readable name for the implementation.
    ///
    /// Kept to a single line, as the value types are: the implementation holds
    /// no state to report.
    public var description: String
    {
        "Bilinear debayering"
    }
}
