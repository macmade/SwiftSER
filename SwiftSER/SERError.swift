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

/// The errors thrown by SwiftSER when reading or validating SER data.
public enum SERError: LocalizedError, CustomStringConvertible, Sendable
{
    /// The provided URL does not point to a readable file (e.g. it is missing
    /// or refers to a directory).
    case invalidFileURL( url: URL )

    /// The file at the given URL exists but its contents could not be read.
    case cannotReadFile( url: URL )

    /// The 178-byte file header is malformed or fails validation; `reason`
    /// describes the specific problem.
    case invalidHeaderData( reason: String )

    /// A frame's pixel data is missing or inconsistent with the geometry the
    /// header declares; `reason` describes the specific problem.
    case invalidFrameData( reason: String )

    /// The trailing block of per-frame timestamps is malformed; `reason`
    /// describes the specific problem.
    case invalidTrailerData( reason: String )

    /// A frame was requested by an index outside the `0 ..< count` range.
    case frameIndexOutOfRange( index: Int, count: Int )

    /// The header declares a ColorID the library does not implement.
    case unsupportedColorID( colorID: Int32 )

    /// The header declares a pixel depth outside the `1...16` range the
    /// specification allows.
    case unsupportedPixelDepth( depth: Int32 )

    /// A low-level data operation failed; `reason` describes the specific
    /// problem.
    case dataError( reason: String )

    /// A Bayer mosaic could not be converted to RGB; `reason` describes the
    /// specific problem.
    case debayerError( reason: String )

    /// A frame could not be rendered to an image; `reason` describes the
    /// specific problem.
    case imageCreationFailed( reason: String )

    /// A sequence could not be encoded to a movie; `reason` describes the
    /// specific problem.
    case movieExportFailed( reason: String )

    /// A human-readable description prefixed with `SER Error:`.
    public var description: String
    {
        "SER Error: \( self.errorDescription ?? "Unknown error" )"
    }

    /// A localized message describing the error and its cause.
    public var errorDescription: String?
    {
        switch self
        {
            case .invalidFileURL(        let url ):             return "Invalid file URL: \( url )"
            case .cannotReadFile(        let url ):             return "Cannot read file: \( url )"
            case .invalidHeaderData(     let reason ):          return "Invalid header data: \( reason )"
            case .invalidFrameData(      let reason ):          return "Invalid frame data: \( reason )"
            case .invalidTrailerData(    let reason ):          return "Invalid trailer data: \( reason )"
            case .frameIndexOutOfRange(  let index, let count ): return "Frame index out of range: \( index ) - frame count: \( count )"
            case .unsupportedColorID(    let colorID ):         return "Unsupported color ID: \( colorID )"
            case .unsupportedPixelDepth( let depth ):           return "Unsupported pixel depth: \( depth )"
            case .dataError(             let reason ):          return "Data error: \( reason )"
            case .debayerError(          let reason ):          return "Debayer error: \( reason )"
            case .imageCreationFailed(   let reason ):          return "Image creation failed: \( reason )"
            case .movieExportFailed(     let reason ):          return "Movie export failed: \( reason )"
        }
    }
}
