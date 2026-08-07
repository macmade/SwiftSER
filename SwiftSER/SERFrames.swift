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

/// The frames of a SER file, addressed on demand.
///
/// A random-access collection over ``SERFile/frameCount`` — the count the file
/// really holds, not the one its header declares. Nothing is stored and no
/// pixel data is read: a frame is built when it is asked for, and its samples
/// only when ``SERFrame/samples`` is.
///
/// Obtained from ``SERFile/frames``.
public struct SERFrames: RandomAccessCollection, CustomStringConvertible
{
    /// The file the frames belong to.
    private let file: SERFile

    /// Creates the collection of a file's frames.
    ///
    /// - Parameter file: The file to address the frames of.
    internal init( file: SERFile )
    {
        self.file = file
    }

    /// The index of the first frame, which is always zero.
    public var startIndex: Int
    {
        0
    }

    /// The index one past the last frame, which is the file's frame count.
    public var endIndex: Int
    {
        self.file.frameCount
    }

    /// The frame at an index.
    ///
    /// - Parameter position: The frame's index, in `startIndex ..< endIndex`.
    /// - Returns: The frame at that index.
    /// - Precondition: `position` addresses a frame the file holds, as every
    ///                 collection's subscript requires. ``SERFile/frame(at:)``
    ///                 reports an out-of-range index as an error instead.
    public subscript( position: Int ) -> SERFrame
    {
        guard let frame = try? self.file.frame( at: position )
        else
        {
            preconditionFailure( "Frame index out of range: \( position ) - frame count: \( self.file.frameCount )" )
        }

        return frame
    }

    /// A human-readable summary of how many frames the collection holds.
    ///
    /// Kept to a single line, as ``SERColorID`` and ``SERTimestamp`` are: a
    /// collection has one fact to report, and the braced form the record types
    /// use would say no more.
    public var description: String
    {
        self.count == 1 ? "1 frame" : "\( self.count ) frames"
    }
}
