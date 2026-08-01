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

/// The pixel layout of a SER file's frames, as stored in header field 3.
///
/// The identifiers fall into three groups: a single gray plane (``mono``), a
/// single-plane color filter mosaic (the eight Bayer cases), and interleaved
/// three-plane color (``rgb`` and ``bgr``). A value the specification does not
/// define is preserved as ``unknown(_:)`` rather than discarded, so a file
/// carrying one can still be read under
/// ``SERParsingOptions/allowUnknownColorID``.
public enum SERColorID: Sendable, Equatable, CustomStringConvertible
{
    /// A single gray plane. Raw value 0.
    case mono

    /// A red/green, green/blue mosaic. Raw value 8.
    case bayerRGGB

    /// A green/red, blue/green mosaic. Raw value 9.
    case bayerGRBG

    /// A green/blue, red/green mosaic. Raw value 10.
    case bayerGBRG

    /// A blue/green, green/red mosaic. Raw value 11.
    case bayerBGGR

    /// A cyan/yellow, yellow/magenta mosaic. Raw value 16.
    case bayerCYYM

    /// A yellow/cyan, magenta/yellow mosaic. Raw value 17.
    case bayerYCMY

    /// A yellow/magenta, cyan/yellow mosaic. Raw value 18.
    case bayerYMCY

    /// A magenta/yellow, yellow/cyan mosaic. Raw value 19.
    case bayerMYYC

    /// Three interleaved planes, red first. Raw value 100.
    case rgb

    /// Three interleaved planes, blue first. Raw value 101.
    case bgr

    /// A value the specification does not define, carrying the raw field.
    case unknown( Int32 )

    /// Creates a color ID from the raw value stored in the header.
    ///
    /// Never fails: an unrecognized value becomes ``unknown(_:)``, so no
    /// information is lost. Rejecting one is the header's decision, made
    /// against ``SERParsingOptions/allowUnknownColorID``.
    ///
    /// - Parameter rawValue: The raw color ID, as stored in header field 3.
    public init( rawValue: Int32 )
    {
        switch rawValue
        {
            case 0:   self = .mono
            case 8:   self = .bayerRGGB
            case 9:   self = .bayerGRBG
            case 10:  self = .bayerGBRG
            case 11:  self = .bayerBGGR
            case 16:  self = .bayerCYYM
            case 17:  self = .bayerYCMY
            case 18:  self = .bayerYMCY
            case 19:  self = .bayerMYYC
            case 100: self = .rgb
            case 101: self = .bgr
            default:  self = .unknown( rawValue )
        }
    }

    /// The raw value as stored in the header.
    public var rawValue: Int32
    {
        switch self
        {
            case .mono:               return 0
            case .bayerRGGB:          return 8
            case .bayerGRBG:          return 9
            case .bayerGBRG:          return 10
            case .bayerBGGR:          return 11
            case .bayerCYYM:          return 16
            case .bayerYCMY:          return 17
            case .bayerYMCY:          return 18
            case .bayerMYYC:          return 19
            case .rgb:                return 100
            case .bgr:                return 101
            case .unknown( let raw ): return raw
        }
    }

    /// The number of planes a frame stores per pixel.
    ///
    /// The specification gives 1 for MONO through BAYER_MYYC and 3 for RGB and
    /// BGR. An ``unknown(_:)`` identifier is assumed to be single-plane, since
    /// that covers every defined identifier but two and there is nothing better
    /// to go on.
    public var numberOfPlanes: Int
    {
        switch self
        {
            case .rgb, .bgr: return 3
            default:         return 1
        }
    }

    /// Whether frames are a color filter mosaic needing to be debayered.
    public var isBayer: Bool
    {
        self.bayerPattern != nil
    }

    /// The mosaic laid over the sensor, or `nil` when frames are not a mosaic.
    public var bayerPattern: SERBayerPattern?
    {
        switch self
        {
            case .bayerRGGB: return .rggb
            case .bayerGRBG: return .grbg
            case .bayerGBRG: return .gbrg
            case .bayerBGGR: return .bggr
            case .bayerCYYM: return .cyym
            case .bayerYCMY: return .ycmy
            case .bayerYMCY: return .ymcy
            case .bayerMYYC: return .myyc
            default:         return nil
        }
    }

    /// The identifier's name, as spelled by the specification.
    public var description: String
    {
        switch self
        {
            case .mono:               return "MONO"
            case .bayerRGGB:          return "BAYER_RGGB"
            case .bayerGRBG:          return "BAYER_GRBG"
            case .bayerGBRG:          return "BAYER_GBRG"
            case .bayerBGGR:          return "BAYER_BGGR"
            case .bayerCYYM:          return "BAYER_CYYM"
            case .bayerYCMY:          return "BAYER_YCMY"
            case .bayerYMCY:          return "BAYER_YMCY"
            case .bayerMYYC:          return "BAYER_MYYC"
            case .rgb:                return "RGB"
            case .bgr:                return "BGR"
            case .unknown( let raw ): return "Unknown (\( raw ))"
        }
    }
}
