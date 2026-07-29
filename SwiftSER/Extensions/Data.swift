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

/// Byte-level helpers used to decode SER data.
///
/// Every offset these methods take is relative to the start of the receiver,
/// not to the buffer a slice was taken from, so passing a slice reads the same
/// bytes as passing standalone data holding a copy of them.
public extension Data
{
    /// Reads a fixed-width integer stored at a byte offset.
    ///
    /// The bytes are combined explicitly rather than reinterpreted in place, so
    /// the offset needs no particular alignment and the result does not depend
    /// on the host's byte order.
    ///
    /// - Parameters:
    ///   - type:         The integer type to decode. Its size determines how
    ///                   many bytes are read.
    ///   - offset:       The offset, in bytes, from the start of the receiver.
    ///   - littleEndian: `true` when the stored bytes run least-significant
    ///                   first, `false` when they run most-significant first.
    /// - Returns: The decoded value. The bytes exactly fill `type`, so a signed
    ///            type reads its stored high bit as a two's-complement sign.
    /// - Throws: ``SERError/dataError(reason:)`` if `offset` is negative or the
    ///           value does not fit entirely within the receiver.
    func integer< T: FixedWidthInteger >( _ type: T.Type, at offset: Int, littleEndian: Bool ) throws -> T
    {
        let bytes   = try self.slice( at: offset, count: MemoryLayout< T >.size )
        let ordered = littleEndian ? Array( bytes.reversed() ) : Array( bytes )

        // Shifting past the type's width discards the overflowing bits rather
        // than trapping, which is exactly the wanted behavior for the sign bit
        // of a signed type.
        return ordered.reduce( T( 0 ) )
        {
            ( $0 << 8 ) | T( truncatingIfNeeded: $1 )
        }
    }

    /// Returns a range of bytes as a slice, without copying them.
    ///
    /// The result shares its storage with the receiver, so slicing a
    /// memory-mapped file does not read the underlying pages. Being a slice,
    /// its indices are the ones it occupies in the receiver rather than
    /// starting at zero — unlike Foundation's `subdata(in:)`, which copies the
    /// bytes into zero-based data. Index the result relative to its own
    /// `startIndex`, or hand it back to the methods of this extension, which
    /// take receiver-relative offsets.
    ///
    /// - Parameters:
    ///   - offset: The offset, in bytes, from the start of the receiver.
    ///   - count:  The number of bytes to read.
    /// - Returns: A slice of the receiver holding the requested bytes.
    /// - Throws: ``SERError/dataError(reason:)`` if `offset` or `count` is
    ///           negative, or if the range extends past the end of the
    ///           receiver.
    func slice( at offset: Int, count: Int ) throws -> Data
    {
        if offset < 0 || count < 0
        {
            throw SERError.dataError( reason: "Negative subrange: \( count ) bytes at offset \( offset )" )
        }

        let ( end, overflow ) = offset.addingReportingOverflow( count )

        if overflow || end > self.count
        {
            throw SERError.dataError( reason: "Subrange of \( count ) bytes at offset \( offset ) exceeds the \( self.count ) available bytes" )
        }

        return self[ self.startIndex + offset ..< self.startIndex + end ]
    }
}
