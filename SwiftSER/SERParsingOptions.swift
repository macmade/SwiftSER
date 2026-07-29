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

/// Options controlling how strictly SER data is parsed and validated.
///
/// Every option is a *leniency flag*: it tolerates input the SER specification
/// does not allow. ``strict`` therefore enables none of them and ``lenient``
/// enables all of them.
public struct SERParsingOptions: OptionSet, Sendable
{
    /// The raw bitmask backing the option set.
    public let rawValue: Int

    /// Creates an option set from its raw bitmask value.
    ///
    /// - Parameter rawValue: The bitmask of enabled options.
    public init( rawValue: Int )
    {
        self.rawValue = rawValue
    }

    /// Accept a file whose 14-byte file ID is not the mandatory
    /// `LUCAM-RECORDER` marker.
    public static let allowInvalidFileID = SERParsingOptions( rawValue: 1 << 0 )

    /// Accept the observer, instrument and telescope strings when they contain
    /// bytes outside the printable ASCII range (`0x20...0x7E`) the
    /// specification requires.
    public static let allowNonPrintableStrings = SERParsingOptions( rawValue: 1 << 1 )

    /// Accept a declared frame count that disagrees with the number of whole
    /// frames the file's length can hold, clamping to what is actually present.
    public static let allowFrameCountMismatch = SERParsingOptions( rawValue: 1 << 2 )

    /// Accept a file that declares a valid start date — and therefore a
    /// timestamp trailer — but carries no trailer at all.
    public static let allowMissingTrailer = SERParsingOptions( rawValue: 1 << 3 )

    /// Accept a timestamp trailer holding fewer than one timestamp per frame,
    /// leaving the missing timestamps undefined.
    public static let allowShortTrailer = SERParsingOptions( rawValue: 1 << 4 )

    /// Accept a ColorID the specification does not define, preserving its raw
    /// value instead of rejecting the file.
    public static let allowUnknownColorID = SERParsingOptions( rawValue: 1 << 5 )

    /// Accept a pixel depth outside the `1...16` range the specification
    /// allows.
    public static let allowOutOfRangePixelDepth = SERParsingOptions( rawValue: 1 << 6 )

    /// Accept timestamps whose two most significant bits are set. Those bits
    /// are undocumented and only the low 62 bits are meaningful, so the value
    /// is masked rather than rejected.
    public static let allowInvalidTimestamps = SERParsingOptions( rawValue: 1 << 7 )

    /// Spec-faithful parsing: rejects any input the SER specification forbids.
    public static let strict: SERParsingOptions = []

    /// Real-world-friendly parsing: tolerates the noncompliant constructs found
    /// in files produced by existing capture software.
    public static let lenient: SERParsingOptions = [
        .allowInvalidFileID,
        .allowNonPrintableStrings,
        .allowFrameCountMismatch,
        .allowMissingTrailer,
        .allowShortTrailer,
        .allowUnknownColorID,
        .allowOutOfRangePixelDepth,
        .allowInvalidTimestamps,
    ]
}
