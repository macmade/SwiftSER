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

/// The color filter mosaic laid over a single-plane SER frame.
///
/// A pattern is named after the 2×2 tile it repeats across the sensor, read
/// row by row: ``rggb`` places red at the top-left, green at the top-right and
/// bottom-left, and blue at the bottom-right. Four patterns use the additive
/// primaries and four the complementary ones; in both groups one filter — green
/// for the additive patterns, yellow for the complementary ones — is sampled
/// twice per tile, which is why it interpolates through its own kernel.
///
/// Derived from ``SERColorID``, which is what the file actually stores.
public enum SERBayerPattern: Sendable, Equatable, CustomStringConvertible
{
    /// Red, green / green, blue.
    case rggb

    /// Green, red / blue, green.
    case grbg

    /// Green, blue / red, green.
    case gbrg

    /// Blue, green / green, red.
    case bggr

    /// Cyan, yellow / yellow, magenta.
    case cyym

    /// Yellow, cyan / magenta, yellow.
    case ycmy

    /// Yellow, magenta / cyan, yellow.
    case ymcy

    /// Magenta, yellow / yellow, cyan.
    case myyc

    /// A single color filter of a mosaic tile.
    public enum Filter: Sendable, Hashable, CustomStringConvertible
    {
        /// The additive red primary.
        case red

        /// The additive green primary.
        case green

        /// The additive blue primary.
        case blue

        /// The complementary of red, passing green and blue.
        case cyan

        /// The complementary of blue, passing red and green.
        case yellow

        /// The complementary of green, passing red and blue.
        case magenta

        /// The filter's name, whose first letter is the one used in a pattern's
        /// four-letter code.
        public var description: String
        {
            switch self
            {
                case .red:     return "Red"
                case .green:   return "Green"
                case .blue:    return "Blue"
                case .cyan:    return "Cyan"
                case .yellow:  return "Yellow"
                case .magenta: return "Magenta"
            }
        }
    }

    /// Whether the pattern uses the complementary filters rather than the
    /// additive primaries.
    ///
    /// The complementary patterns need an extra transform to reach RGB, which
    /// the specification does not define, so they are handled separately by the
    /// debayering stage.
    public var isCMY: Bool
    {
        switch self
        {
            case .cyym, .ycmy, .ymcy, .myyc: return true
            default:                         return false
        }
    }

    /// The pattern's 2×2 tile, row-major.
    ///
    /// Exactly four filters, ordered top-left, top-right, bottom-left,
    /// bottom-right — the same order the four-letter code spells out. The tile
    /// repeats from the frame's upper-left pixel, which the specification
    /// defines as the first stored pixel.
    public var tile: [ Filter ]
    {
        switch self
        {
            case .rggb: return [ .red,     .green,   .green,   .blue    ]
            case .grbg: return [ .green,   .red,     .blue,    .green   ]
            case .gbrg: return [ .green,   .blue,    .red,     .green   ]
            case .bggr: return [ .blue,    .green,   .green,   .red     ]
            case .cyym: return [ .cyan,    .yellow,  .yellow,  .magenta ]
            case .ycmy: return [ .yellow,  .cyan,    .magenta, .yellow  ]
            case .ymcy: return [ .yellow,  .magenta, .cyan,    .yellow  ]
            case .myyc: return [ .magenta, .yellow,  .yellow,  .cyan    ]
        }
    }

    /// The pattern's four-letter code, as used by the specification's ColorID
    /// names.
    public var description: String
    {
        switch self
        {
            case .rggb: return "RGGB"
            case .grbg: return "GRBG"
            case .gbrg: return "GBRG"
            case .bggr: return "BGGR"
            case .cyym: return "CYYM"
            case .ycmy: return "YCMY"
            case .ymcy: return "YMCY"
            case .myyc: return "MYYC"
        }
    }
}
