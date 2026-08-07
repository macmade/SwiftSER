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

#if canImport( Accelerate )
import Accelerate
#endif

/// A single image frame of a SER file.
///
/// A frame is a *view*: creating one costs nothing beyond slicing the file's
/// bytes and reading the frame's own trailer entry, and no pixel data is
/// examined until ``samples`` is asked for. That is what lets a multi-gigabyte
/// capture be enumerated frame by frame.
///
/// Frames come from ``SERFile/frame(at:)`` or ``SERFile/frames``, which is what
/// guarantees ``rawData`` holds the whole frame.
public struct SERFrame: Sendable, CustomStringConvertible
{
    /// The frame's position in the file, counting from zero.
    public let index: Int

    /// The header of the file the frame belongs to.
    public let header: SERHeader

    /// The instant the frame was captured, or `nil` when the file carries no
    /// timestamp for it.
    public let timestamp: Date?

    /// The frame's pixel data, exactly as the file stores it.
    ///
    /// A slice of the file's own bytes, so reading it does not copy them. No
    /// decoding of any kind is applied: the bytes are in the file's byte order,
    /// and the channels are in the file's channel order.
    ///
    /// - Important: Being a slice, its indices are the ones it occupies in the
    ///   file, not indices starting at zero — the first byte of frame 1 of a
    ///   4-byte-frame file is at index 182, and `rawData[ 0 ]` would trap.
    ///   Index it relative to its own `startIndex`, or take a zero-based copy
    ///   with `Array( frame.rawData )`.
    public let rawData: Data

    /// Creates a frame from its position and its bytes.
    ///
    /// - Parameters:
    ///   - index:     The frame's position in the file.
    ///   - header:    The header of the file the frame belongs to.
    ///   - timestamp: The instant the frame was captured, if the file records
    ///                one.
    ///   - rawData:   The frame's pixel data, which must hold at least
    ///                ``SERHeader/bytesPerFrame`` bytes for ``samples`` to
    ///                decode.
    internal init( index: Int, header: SERHeader, timestamp: Date?, rawData: Data )
    {
        self.index     = index
        self.header    = header
        self.timestamp = timestamp
        self.rawData   = rawData
    }

    /// The frame's decoded samples: interleaved, row-major, non-normalized.
    ///
    /// The array holds ``SERHeader/samplesPerFrame`` values, running from the
    /// image's upper-left pixel along each row in turn, with a three-plane
    /// pixel's channels adjacent. Values are the ones the file stores, widened
    /// to `Double` and *not* rescaled — ``SERHeader/sampleRange`` says what full
    /// scale is for them, since a sample's alignment within its container
    /// depends on the depth. A file that leaves the padding bits of a sub-byte
    /// depth set can exceed that range, which is why it documents itself as a
    /// bound to clamp against rather than one to trust.
    ///
    /// Three things happen along the way, and each of them is a way to read a
    /// SER file wrongly:
    ///
    /// - 16-bit samples are byte-swapped according to
    ///   ``SERHeader/isLittleEndian``, which governs image data only.
    /// - 16-bit samples are widened as *unsigned*, so a sample above 32767 stays
    ///   positive.
    /// - A ``SERColorID/bgr`` frame has its channels reordered to RGB, so
    ///   everything downstream sees one channel order.
    ///
    /// Decoding runs on each access rather than being cached, so the result is
    /// worth holding on to when it is needed more than once.
    ///
    /// - Throws: ``SERError/invalidFrameData(reason:)`` if ``rawData`` is
    ///           shorter than the header's frame size.
    public var samples: [ Double ]
    {
        get throws
        {
            try self.decodedSamples( accelerated: true )
        }
    }

    /// Decodes the frame's samples through a chosen widening implementation.
    ///
    /// Both implementations are always compiled, so the plain-Swift one does not
    /// go untested wherever Accelerate happens to be available. ``samples`` asks
    /// for the accelerated one, which falls back on its own when the platform
    /// offers no Accelerate.
    ///
    /// - Parameter accelerated: Whether to widen through Accelerate when the
    ///                          platform provides it.
    /// - Returns: The frame's samples, interleaved and row-major.
    /// - Throws: ``SERError/invalidFrameData(reason:)`` if ``rawData`` is
    ///           shorter than the header's frame size.
    internal func decodedSamples( accelerated: Bool ) throws -> [ Double ]
    {
        // Stated as what the decoding loops below actually read — one container
        // of ``SERHeader/bytesPerSample`` bytes for each of
        // ``SERHeader/samplesPerFrame`` samples — rather than as
        // ``SERHeader/bytesPerFrame``, which is the same number by
        // construction. The unsafe reads are then bounded by this guard alone,
        // with no appeal to how the header derived its frame size.
        let ( required, overflow ) = self.header.samplesPerFrame.multipliedReportingOverflow( by: self.header.bytesPerSample )

        guard overflow == false
        else
        {
            throw SERError.invalidFrameData( reason: "Frame \( self.index ) declares \( self.header.samplesPerFrame ) samples of \( self.header.bytesPerSample ) bytes, which overflows" )
        }

        guard self.rawData.count >= required
        else
        {
            throw SERError.invalidFrameData( reason: "Frame \( self.index ) holds \( self.rawData.count ) bytes, where a frame is \( required )" )
        }

        var samples = self.widenedSamples( accelerated: accelerated )

        // Reordered in place. The array has just been built and is held nowhere
        // else, so mutating it costs no copy of what can be tens of megabytes.
        if self.header.colorID == .bgr
        {
            SERFrame.reorderToRGB( &samples )
        }

        return samples
    }

    /// Widens the frame's stored containers to `Double`, in stored order.
    ///
    /// - Parameter accelerated: Whether to widen through Accelerate when the
    ///                          platform provides it.
    /// - Returns: One value per sample, in the file's own channel order.
    private func widenedSamples( accelerated: Bool ) -> [ Double ]
    {
        let count = self.header.samplesPerFrame

        return self.rawData.withUnsafeBytes
        {
            bytes in

            guard self.header.bytesPerSample == 2
            else
            {
                return SERFrame.widened( bytes: bytes, count: count, accelerated: accelerated )
            }

            // A scratch buffer rather than an array: the containers exist only
            // for the length of this call, and a frame of them runs to twice
            // its sample count in bytes — tens of megabytes for a large capture.
            return withUnsafeTemporaryAllocation( of: UInt16.self, capacity: count )
            {
                containers in

                SERFrame.fill( containers, from: bytes, littleEndian: self.header.isLittleEndian )

                return SERFrame.widened( containers: containers, accelerated: accelerated )
            }
        }
    }

    /// Widens one-byte samples to `Double`.
    ///
    /// - Parameters:
    ///   - bytes:       The frame's pixel data.
    ///   - count:       The number of samples to read, which `bytes` holds a
    ///                  byte for.
    ///   - accelerated: Whether to widen through Accelerate when the platform
    ///                  provides it.
    /// - Returns: One value per sample.
    private static func widened( bytes: UnsafeRawBufferPointer, count: Int, accelerated: Bool ) -> [ Double ]
    {
        guard count > 0
        else
        {
            return []
        }

        #if canImport( Accelerate )
        if accelerated, let input = bytes.bindMemory( to: UInt8.self ).baseAddress
        {
            return [ Double ]( unsafeUninitializedCapacity: count )
            {
                buffer, initialized in

                guard let output = buffer.baseAddress
                else
                {
                    initialized = 0

                    return
                }

                vDSP_vfltu8D( input, 1, output, 1, vDSP_Length( count ) )

                initialized = count
            }
        }
        #endif

        // Read by index rather than through a transformation of the receiver:
        // this is the per-sample inner loop, and it reads a raw buffer whose
        // bytes are the samples themselves.
        return ( 0 ..< count ).map { Double( bytes[ $0 ] ) }
    }

    /// Widens two-byte samples to `Double`.
    ///
    /// - Parameters:
    ///   - containers:  The samples, already in the host's byte order.
    ///   - accelerated: Whether to widen through Accelerate when the platform
    ///                  provides it.
    /// - Returns: One value per sample, unsigned, so a sample above 32767 stays
    ///            positive.
    private static func widened( containers: UnsafeMutableBufferPointer< UInt16 >, accelerated: Bool ) -> [ Double ]
    {
        guard containers.isEmpty == false
        else
        {
            return []
        }

        #if canImport( Accelerate )
        if accelerated, let input = containers.baseAddress
        {
            return [ Double ]( unsafeUninitializedCapacity: containers.count )
            {
                buffer, initialized in

                guard let output = buffer.baseAddress
                else
                {
                    initialized = 0

                    return
                }

                vDSP_vfltu16D( input, 1, output, 1, vDSP_Length( containers.count ) )

                initialized = containers.count
            }
        }
        #endif

        return containers.map { Double( $0 ) }
    }

    /// Assembles two-byte samples from the frame's bytes.
    ///
    /// - Parameters:
    ///   - containers:   The buffer to fill, whose length is the number of
    ///                   samples to read. `bytes` holds two bytes for each.
    ///   - bytes:        The frame's pixel data.
    ///   - littleEndian: `true` when a sample's bytes run least-significant
    ///                   first, which is what header field 4 records.
    private static func fill( _ containers: UnsafeMutableBufferPointer< UInt16 >, from bytes: UnsafeRawBufferPointer, littleEndian: Bool )
    {
        // Indexed writes into raw memory: this is the per-sample inner loop.
        // A frame's samples start at an offset nothing guarantees the alignment
        // of, hence `loadUnaligned`; converting the loaded pair through the
        // matching byte order keeps the result independent of the host's. The
        // buffer arrives uninitialized, so each element is initialized rather
        // than assigned to.
        containers.indices.forEach
        {
            let stored = bytes.loadUnaligned( fromByteOffset: $0 * 2, as: UInt16.self )

            containers.initializeElement( at: $0, to: littleEndian ? UInt16( littleEndian: stored ) : UInt16( bigEndian: stored ) )
        }
    }

    /// A multi-line, human-readable summary of the frame.
    ///
    /// Reports the frame's own facts and not its ``header``, whose description
    /// is itself multi-line and would read worse nested here than the default
    /// reflection this replaces.
    public var description: String
    {
        """
        SERFrame
        {
            Index:     \( self.index )
            Timestamp: \( self.timestamp.map { "\( $0 )" } ?? "Unknown" )
            Bytes:     \( self.rawData.count )
            Samples:   \( self.header.samplesPerFrame )
        }
        """
    }

    /// Reorders a frame's channels from BGR to RGB, in place.
    ///
    /// - Parameter samples: The frame's samples, three per pixel, blue first.
    ///                      Left red first.
    private static func reorderToRGB( _ samples: inout [ Double ] )
    {
        // Three samples at a time, exchanging the first and the last: a BGR
        // pixel becomes an RGB one. The bound leaves out any trailing partial
        // pixel, which a three-plane frame never has.
        stride( from: 0, to: samples.count - ( samples.count % 3 ), by: 3 ).forEach
        {
            samples.swapAt( $0, $0 + 2 )
        }
    }
}
