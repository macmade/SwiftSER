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

#if canImport( AVFoundation )

import Foundation

/// The pace a SER sequence's frames are written at.
///
/// The movie is written at one constant rate either way: SER frames are stamped
/// as they are captured and are rarely evenly spaced, and giving each frame the
/// instant it carries would produce a movie that plays in fits and starts.
public enum SERMovieFrameRate: Sendable, Equatable, CustomStringConvertible
{
    /// A rate the caller chooses, in frames per second.
    case constant( Double )

    /// The average rate the capture was recorded at, taken from the timestamp
    /// trailer.
    ///
    /// The rate is the number of frames from the first stamped one to the last
    /// divided into the time between them — counted across frame *positions*, so
    /// that a trailer missing some of its entries still reports the pace the
    /// capture ran at rather than a fraction of it.
    ///
    /// `fallback` is used instead whenever the trailer cannot name a rate, which
    /// is any of:
    ///
    /// - the file carries no trailer, or a short one leaving fewer than two
    ///   frames stamped;
    /// - the file holds fewer than two frames, so there is no interval at all;
    /// - the first and last stamps do not advance, which a corrupt trailer or
    ///   one written with a single repeated instant produces;
    /// - the stamps run backwards;
    /// - the capture ran faster than a movie can be written, which is more than
    ///   30000 frames a second — the resolution the times are stored at, beyond
    ///   which two frames would share a tick.
    ///
    /// Stamps that advance overall but wander in between are *not* a fallback
    /// case: only the first and the last are consulted, so a few frames out of
    /// order still yield the capture's average pace.
    case fromTimestamps( fallback: Double )

    /// A human-readable summary of the pace.
    ///
    /// Kept to a single line, as the other value types are.
    public var description: String
    {
        switch self
        {
            case .constant( let rate ):           return "\( rate ) fps"
            case .fromTimestamps( let fallback ): return "From timestamps, or \( fallback ) fps"
        }
    }
}

#endif
