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

/// Rendering a frame to a Core Graphics image.
///
/// Guarded by `canImport( CoreGraphics )`, so the parser itself stays
/// Foundation-only and portable.
public extension SERFrame
{
    /// The frame as a Core Graphics image.
    ///
    /// The image holds one channel for a single-plane frame and three for
    /// ``SERColorID/rgb`` and ``SERColorID/bgr``, at eight bits per component
    /// for a depth of 1 to 8 and sixteen for a depth of 9 to 16 — so nothing the
    /// file stores is quantized away on the way out.
    ///
    /// - Important: A mosaic frame is *not* debayered here. A frame knows
    ///   nothing of the file's ``SERFile/debayering``, so a
    ///   ``SERColorID/isBayer`` frame renders as the single gray plane it
    ///   physically is, which is the picture to reach for when inspecting a raw
    ///   mosaic. ``SERFile/cgImage(ofFrame:scaled:)`` is the one that resolves
    ///   the mosaic to color.
    ///
    /// - Parameter scaled: Whether to stretch the frame's
    ///                     ``SERHeader/sampleRange`` over the output's full
    ///                     range. Pass `true` for a picture to look at: the
    ///                     specification stores a depth of 9 to 16 bits
    ///                     LSB-aligned, so a 12-bit frame occupies `0...4095` of
    ///                     a 16-bit component and renders at roughly 6%
    ///                     brightness untouched. Pass `false` for the stored
    ///                     values, as ``samples`` decodes them.
    /// - Returns: The rendered image, holding its own copy of the pixels.
    /// - Throws: ``SERError/invalidFrameData(reason:)`` if ``rawData`` is
    ///           shorter than the header's frame size, or
    ///           ``SERError/imageCreationFailed(reason:)`` if Core Graphics
    ///           declines the image.
    func cgImage( scaled: Bool ) throws -> CGImage
    {
        try SERFrame.cgImage( samples: self.samples, header: self.header, planes: self.header.numberOfPlanes, scaled: scaled )
    }
}

/// The rendering itself, shared with ``SERFile/cgImage(ofFrame:scaled:)``.
///
/// Kept apart from the public extension above so that the file rendering a
/// frame's own samples and the file rendering its debayered ones go through the
/// same code, rather than through two implementations of the same conversion.
internal extension SERFrame
{
    /// The largest value an eight-bit component takes.
    private static let maximumByteComponent: Double = 255

    /// The largest value a sixteen-bit component takes.
    private static let maximumWordComponent: Double = 65535

    /// Renders interleaved samples to a Core Graphics image.
    ///
    /// The layout follows the header: `width` × `height` pixels of `planes`
    /// components each, at ``SERHeader/bytesPerSample`` bytes per component. One
    /// plane renders into a device gray space and three into a device RGB one —
    /// device spaces because the format records no colorimetry at all, so
    /// claiming a calibrated one would be an invention.
    ///
    /// Twenty-four and forty-eight bits per pixel are not layouts a
    /// `CGBitmapContext` accepts, but `CGImageCreate` does take them, which is
    /// what lets three planes be handed over without an alpha channel invented
    /// to pad them. What holds that is the test suite, which draws every layout
    /// through Core Graphics and round-trips it through PNG rather than only
    /// reading back the bytes handed in.
    ///
    /// - Parameters:
    ///   - samples: The pixel samples: interleaved, row-major and
    ///              non-normalized, holding `width * height * planes` values.
    ///              A value that names no number renders black, since converting
    ///              one to a component would otherwise trap — only reachable
    ///              through a consumer's own ``SERDebayering``.
    ///   - header:  The header the geometry and sample range come from.
    ///   - planes:  The number of components a pixel of `samples` holds, which
    ///              is the header's own count except for a debayered mosaic,
    ///              whose single plane has become three.
    ///   - scaled:  Whether to stretch ``SERHeader/sampleRange`` over the
    ///              output's full range.
    /// - Returns: The rendered image, holding its own copy of the pixels.
    /// - Throws: ``SERError/imageCreationFailed(reason:)`` if no color space
    ///           describes `planes` components, if the geometry overflows, if
    ///           `samples` does not fill it, or if Core Graphics declines the
    ///           image.
    static func cgImage( samples: [ Double ], header: SERHeader, planes: Int, scaled: Bool ) throws -> CGImage
    {
        let width  = Int( header.imageWidth )
        let height = Int( header.imageHeight )

        guard let space = SERFrame.colorSpace( planes: planes )
        else
        {
            throw SERError.imageCreationFailed( reason: "No color space describes a pixel of \( planes ) planes" )
        }

        let ( componentsPerRow, rowOverflow   ) = width.multipliedReportingOverflow( by: planes )
        let ( componentCount,   countOverflow ) = componentsPerRow.multipliedReportingOverflow( by: height )
        let ( bytesPerRow,      bytesOverflow ) = componentsPerRow.multipliedReportingOverflow( by: header.bytesPerSample )
        let ( byteCount,        totalOverflow ) = componentCount.multipliedReportingOverflow( by: header.bytesPerSample )

        // The header bounds a frame at one byte per sample per plane, and a
        // debayered mosaic is three times that, so these only fire for a
        // geometry no capture reaches — and on 64-bit, for none at all.
        guard rowOverflow == false, countOverflow == false, bytesOverflow == false, totalOverflow == false
        else
        {
            throw SERError.imageCreationFailed( reason: "A \( width )x\( height ) image of \( planes ) planes overflows" )
        }

        guard samples.count == componentCount
        else
        {
            throw SERError.imageCreationFailed( reason: "A \( width )x\( height ) image of \( planes ) planes holds \( componentCount ) samples, found \( samples.count )" )
        }

        let components = SERFrame.components( of: samples, range: header.sampleRange, bytesPerSample: header.bytesPerSample, scaled: scaled )

        // Unreachable: the sample count was just checked against the geometry,
        // and the components are one or two bytes each of exactly those samples.
        // Kept because the image's `bytesPerRow` is derived from the geometry
        // rather than from what was built, so Core Graphics would otherwise be
        // free to read past the buffer if the two ever parted company.
        guard components.count == byteCount
        else
        {
            throw SERError.imageCreationFailed( reason: "A \( width )x\( height ) image needs \( byteCount ) bytes of pixel data, built \( components.count )" )
        }

        guard let provider = CGDataProvider( data: components as CFData )
        else
        {
            throw SERError.imageCreationFailed( reason: "Cannot provide \( byteCount ) bytes of pixel data for a \( width )x\( height ) image" )
        }

        // `shouldInterpolate` is false: these are sensor samples, and a viewer
        // magnifying them is looking for the pixels rather than for a smooth
        // picture.
        guard let image = CGImage(
            width:             width,
            height:            height,
            bitsPerComponent:  header.bytesPerSample * 8,
            bitsPerPixel:      header.bytesPerSample * 8 * planes,
            bytesPerRow:       bytesPerRow,
            space:             space,
            bitmapInfo:        SERFrame.bitmapInfo( bytesPerSample: header.bytesPerSample ),
            provider:          provider,
            decode:            nil,
            shouldInterpolate: false,
            intent:            .defaultIntent
        )
        else
        {
            throw SERError.imageCreationFailed( reason: "Core Graphics declined a \( width )x\( height ) image of \( planes ) planes at \( header.bytesPerSample * 8 ) bits per component" )
        }

        return image
    }

    /// The color space a pixel of a given number of planes renders into.
    ///
    /// - Parameter planes: The number of components a pixel holds.
    /// - Returns: A device gray space for one plane and a device RGB one for
    ///            three, or `nil` for any other count, which the format defines
    ///            no meaning for.
    private static func colorSpace( planes: Int ) -> CGColorSpace?
    {
        switch planes
        {
            case 1:  return CGColorSpaceCreateDeviceGray()
            case 3:  return CGColorSpaceCreateDeviceRGB()
            default: return nil
        }
    }

    /// The bitmap layout the rendered components are described by.
    ///
    /// - Parameter bytesPerSample: The width of one stored sample, in bytes.
    /// - Returns: Opaque components, in the host's byte order where that is a
    ///            question at all — which for a one-byte component it is not.
    private static func bitmapInfo( bytesPerSample: Int ) -> CGBitmapInfo
    {
        guard bytesPerSample == 2
        else
        {
            return CGBitmapInfo( rawValue: CGImageAlphaInfo.none.rawValue )
        }

        return CGBitmapInfo( rawValue: CGImageAlphaInfo.none.rawValue | CGImageByteOrderInfo.order16Host.rawValue )
    }

    /// Converts samples to the components the image is built from.
    ///
    /// - Parameters:
    ///   - samples:        The pixel samples, whose count the caller has already
    ///                     checked against the geometry, so that multiplying it
    ///                     by `bytesPerSample` cannot overflow.
    ///   - range:          The range a conforming file's samples occupy, which
    ///                     scaling stretches over the output's own.
    ///   - bytesPerSample: The width of one component, in bytes, which
    ///                     ``SERHeader/bytesPerSample`` gives as 1 or 2. Any
    ///                     other value is written as one byte, since there is no
    ///                     third component width to write.
    ///   - scaled:         Whether to apply that stretch.
    /// - Returns: The components, one or two bytes each, in sample order.
    private static func components( of samples: [ Double ], range: ClosedRange< Double >, bytesPerSample: Int, scaled: Bool ) -> Data
    {
        let maximum = bytesPerSample == 2 ? SERFrame.maximumWordComponent : SERFrame.maximumByteComponent

        // A sample range always reaches at least 128, so the division is safe;
        // the test is there because nothing in this function's own signature
        // says so.
        let factor = scaled && range.upperBound > 0 ? maximum / range.upperBound : 1

        var data = Data( count: samples.count * bytesPerSample )

        data.withUnsafeMutableBytes
        {
            buffer in

            samples.withUnsafeBufferPointer
            {
                input in

                // Two concrete loops rather than one written over a generic
                // integer: this is the per-sample inner loop, and the generic
                // form measured four times slower, since it does not specialize
                // across the call. Both write through `storeBytes`, which since
                // SE-0349 carries no alignment requirement — a `Data` short
                // enough to be stored inline gives out an address aligned for a
                // byte and nothing more, which binding it to `UInt16` would
                // assume.
                guard bytesPerSample == 2
                else
                {
                    input.indices.forEach
                    {
                        buffer.storeBytes( of: UInt8( SERFrame.component( of: input[ $0 ], factor: factor, maximum: maximum ) ), toByteOffset: $0, as: UInt8.self )
                    }

                    return
                }

                // Words in the host's byte order, which is what
                // ``bitmapInfo(bytesPerSample:)`` declares.
                input.indices.forEach
                {
                    buffer.storeBytes( of: UInt16( SERFrame.component( of: input[ $0 ], factor: factor, maximum: maximum ) ), toByteOffset: $0 * 2, as: UInt16.self )
                }
            }
        }

        return data
    }

    /// Converts one sample to its component value.
    ///
    /// - Parameters:
    ///   - sample:  The stored sample.
    ///   - factor:  What to multiply it by, which is one when nothing is being
    ///              scaled.
    ///   - maximum: The largest value a component takes.
    /// - Returns: A whole number in `0...maximum`, rounded to the nearest with
    ///            halves going away from zero.
    private static func component( of sample: Double, factor: Double, maximum: Double ) -> Double
    {
        // A sample that is not a number cannot be clamped into range — `max`
        // and `min` both pass a NaN straight through, and converting one to an
        // integer traps — so it is answered for before the arithmetic. The
        // infinities are not: clamping resolves them to the ends of the range.
        guard sample.isNaN == false
        else
        {
            return 0
        }

        // The clamp is what makes the conversion total. The specification does
        // not have the padding bits of a sub-byte depth validated, so a sample
        // can exceed ``SERHeader/sampleRange`` — see its own documentation —
        // and scaling would then carry it past full scale.
        return min( max( sample * factor, 0 ), maximum ).rounded()
    }
}

#endif
