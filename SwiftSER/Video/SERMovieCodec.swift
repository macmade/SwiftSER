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

import AVFoundation
import Foundation

/// The codec a SER sequence is encoded with.
///
/// SwiftSER names its own codecs rather than taking an `AVVideoCodecType`, so
/// the ones it has actually been exercised against are the ones a caller can
/// ask for.
///
/// - Important: ``h264`` and ``hevc`` encode in macroblocks and round an odd
///              frame dimension *down* to the next even one — a 1281×961
///              capture comes back as 1280×960. The two ProRes codecs carry an
///              odd size through untouched. This is the encoder's doing, not
///              the writer's, and nothing can be done about it beyond choosing
///              a different codec.
public enum SERMovieCodec: Sendable, CaseIterable, Equatable, CustomStringConvertible
{
    /// H.264, the most widely playable of the four, and lossy.
    case h264

    /// HEVC — smaller than ``h264`` at the same quality, and lossy.
    case hevc

    /// Apple ProRes 422, visually lossless and much larger.
    case proRes422

    /// Apple ProRes 4444, the highest quality of the four and the largest.
    ///
    /// Highest quality among these codecs, which is not the same as preserving
    /// the capture: every frame reaches the encoder as 8-bit BGRA, so a 16-bit
    /// capture gives up its depth on the way out whichever of the four is used.
    case proRes4444

    /// The AVFoundation codec this names.
    internal var videoCodecType: AVVideoCodecType
    {
        switch self
        {
            case .h264:       return .h264
            case .hevc:       return .hevc
            case .proRes422:  return .proRes422
            case .proRes4444: return .proRes4444
        }
    }

    /// Whether the codec preserves a frame dimension that is not even.
    ///
    /// `false` for the two macroblock codecs, which round down. Public so that
    /// the caveat the type documents can be answered in code — a caller
    /// exporting a capture of odd geometry can pick a codec that keeps it, or
    /// warn that the movie will not be the size the capture was.
    public var preservesOddDimensions: Bool
    {
        switch self
        {
            case .h264, .hevc:              return false
            case .proRes422, .proRes4444:   return true
        }
    }

    /// The codec's common name.
    public var description: String
    {
        switch self
        {
            case .h264:       return "H.264"
            case .hevc:       return "HEVC"
            case .proRes422:  return "ProRes 422"
            case .proRes4444: return "ProRes 4444"
        }
    }
}

#endif
