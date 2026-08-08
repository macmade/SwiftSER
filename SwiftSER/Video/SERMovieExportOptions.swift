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

/// How a SER sequence is encoded to a movie.
///
/// The destination is not here: it is what ``SERMovieWriter/write(file:to:progress:)``
/// takes, since it is where the movie goes rather than a setting describing it.
public struct SERMovieExportOptions: Sendable, Equatable, CustomStringConvertible
{
    /// The codec to encode with.
    public var codec: SERMovieCodec

    /// The pace to write the frames at.
    public var frameRate: SERMovieFrameRate

    /// Whether to stretch each frame's ``SERHeader/sampleRange`` over the full
    /// output range.
    ///
    /// Almost always `true`: the specification stores a depth of 9 to 16 bits
    /// LSB-aligned, so a 12-bit capture occupies `0...4095` of its container and
    /// encodes to a movie that plays back nearly black untouched. `false` writes
    /// the stored values, which is what an already full-scale capture wants.
    public var scaled: Bool

    /// Creates a set of export options.
    ///
    /// - Parameters:
    ///   - codec:     The codec to encode with.
    ///   - frameRate: The pace to write the frames at.
    ///   - scaled:    Whether to stretch each frame's sample range over the full
    ///                output range.
    public init( codec: SERMovieCodec, frameRate: SERMovieFrameRate, scaled: Bool )
    {
        self.codec     = codec
        self.frameRate = frameRate
        self.scaled    = scaled
    }

    /// A human-readable summary of the options.
    ///
    /// Kept to a single line, as the other value types are.
    public var description: String
    {
        "\( self.codec ), \( self.frameRate )\( self.scaled ? ", scaled" : "" )"
    }
}

#endif
