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

#if canImport( CoreGraphics )

import CoreGraphics
import Foundation

/// Rendering a file's frames to Core Graphics images.
///
/// Guarded by `canImport( CoreGraphics )`, so the parser itself stays
/// Foundation-only and portable.
public extension SERFile
{
    /// A frame as a Core Graphics image, with any color filter mosaic resolved.
    ///
    /// The one call to make whatever the file is: a mosaic frame is debayered
    /// first — through ``debayering`` when one is installed and claims the
    /// pattern, and through ``SERBilinearDebayering`` otherwise — so the image
    /// is color for every color file. A frame that carries no mosaic is rendered
    /// exactly as ``SERFrame/cgImage(scaled:)`` would render it.
    ///
    /// - Note: Unlike addressing a frame, this materializes it, and twice over:
    ///   the samples and the components built from them are both live while the
    ///   image is assembled — worth knowing when sizing a pipeline over a
    ///   capture the rest of the library never loads.
    ///
    /// - Parameters:
    ///   - index:  The frame's index, in `0 ..< frameCount`.
    ///   - scaled: Whether to stretch the frame's ``SERHeader/sampleRange`` over
    ///             the output's full range. Pass `true` for a picture to look
    ///             at: a 12-bit capture occupies `0...4095` of a 16-bit
    ///             component and renders at roughly 6% brightness untouched.
    /// - Returns: The rendered image, holding its own copy of the pixels.
    /// - Throws: ``SERError/frameIndexOutOfRange(index:count:)`` if the index
    ///           falls outside the frames the file holds;
    ///           ``SERError/invalidFrameData(reason:)`` if the frame's bytes
    ///           cannot be decoded; ``SERError/imageCreationFailed(reason:)`` if
    ///           Core Graphics declines the image; or anything
    ///           ``debayeredSamples(ofFrame:)`` raises, which under the default
    ///           ``SERDebayerFailurePolicy/fallBackToBuiltIn`` is nothing a
    ///           consumer's implementation did.
    func cgImage( ofFrame index: Int, scaled: Bool ) throws -> CGImage
    {
        // Debayering turns a mosaic's single plane into three; every other file
        // keeps the plane count its color ID declares.
        let samples = try self.debayeredSamples( ofFrame: index )
        let planes  = self.header.bayerPattern == nil ? self.header.numberOfPlanes : SERBilinearDebayering.planeCount

        return try SERFrame.cgImage( samples: samples, header: self.header, planes: planes, scaled: scaled )
    }
}

#endif
