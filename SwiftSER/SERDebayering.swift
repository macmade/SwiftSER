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

/// An implementation turning a color filter mosaic into three-channel RGB.
///
/// SwiftSER ships ``SERBilinearDebayering``, which covers all eight patterns
/// the format defines, so the library always produces a result on its own.
/// Conform to this protocol and set ``SERFile/debayering`` to hand the work to
/// a better implementation instead.
///
/// Taking over is not all-or-nothing. An implementation reports which patterns
/// it handles through ``supports(pattern:)``, and SwiftSER debayers the rest
/// itself; one that throws is answered by ``SERFile/debayerFailurePolicy``. A
/// file therefore always has an implementation behind it, whatever a consumer's
/// own covers.
///
/// The mosaic arrives as ``SERFrame/samples`` gives it: interleaved — one
/// sample per pixel for a mosaic — row-major from the image's upper-left pixel,
/// and *not* rescaled, so its values run to ``SERHeader/sampleRange`` rather
/// than to any normalized full scale.
public protocol SERDebayering
{
    /// Whether this implementation handles the given pattern.
    ///
    /// SwiftSER asks before every call. Declining is not an error: a pattern
    /// answered with `false` goes to SwiftSER's own ``SERBilinearDebayering``
    /// regardless of ``SERFile/debayerFailurePolicy``.
    ///
    /// - Parameter pattern: The mosaic laid over the frames of the file being
    ///                      read.
    /// - Returns: `true` to debayer the pattern, `false` to leave it to
    ///            SwiftSER.
    func supports( pattern: SERBayerPattern ) -> Bool

    /// Debayers one frame's mosaic.
    ///
    /// - Parameters:
    ///   - mosaic:  The frame's samples: single-plane, row-major and
    ///              non-normalized, holding `width * height` values.
    ///   - width:   The image's width, in pixels.
    ///   - height:  The image's height, in pixels.
    ///   - pattern: The mosaic laid over the sensor, which
    ///              ``supports(pattern:)`` has already accepted.
    /// - Returns: Interleaved RGB, row-major, holding `width * height * 3`
    ///            values. A result of any other length is treated as a failure.
    /// - Throws: Any error. What SwiftSER does with it is decided by
    ///           ``SERFile/debayerFailurePolicy``.
    func debayer( mosaic: [ Double ], width: Int, height: Int, pattern: SERBayerPattern ) throws -> [ Double ]
}
