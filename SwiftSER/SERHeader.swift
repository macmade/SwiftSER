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

/// The fixed-size header opening every SER file.
///
/// The header is a flat run of thirteen fields at fixed offsets, with no block
/// or chunk structure: parsing is a straight field decode. Every integer field
/// is little-endian regardless of ``isLittleEndian``, which governs the byte
/// order of 16-bit *image data* only.
///
/// Alongside the stored fields, the header exposes the geometry the rest of the
/// library addresses frames with — ``numberOfPlanes``, ``bytesPerPixel`` and
/// ``bytesPerFrame`` — computed once and checked for overflow, so a corrupt
/// header is rejected rather than yielding a wrapped frame size.
public struct SERHeader: Sendable, CustomStringConvertible
{
    /// The size, in bytes, of a SER header. Fixed by the specification at 178.
    public static let size = 178

    /// The content the file ID field is required to hold.
    public static let fileIDMarker = "LUCAM-RECORDER"

    /// The width, in bytes, of the file ID field.
    private static let fileIDLength = 14

    /// The width, in bytes, of each of the observer, instrument and telescope
    /// fields.
    private static let nameLength = 40

    /// The byte offset of each field within the header.
    ///
    /// The specification lists the fields in order with their lengths, but no
    /// absolute offsets. These are the running sums of those lengths, and add
    /// up to ``size``.
    private enum Offset
    {
        /// The offset of the file ID.
        static let fileID = 0

        /// The offset of the Lumenera camera series ID.
        static let luID = 14

        /// The offset of the color ID.
        static let colorID = 18

        /// The offset of the 16-bit image data byte-order flag.
        static let littleEndian = 22

        /// The offset of the image width.
        static let imageWidth = 26

        /// The offset of the image height.
        static let imageHeight = 30

        /// The offset of the pixel depth per plane.
        static let pixelDepthPerPlane = 34

        /// The offset of the frame count.
        static let frameCount = 38

        /// The offset of the observer name.
        static let observer = 42

        /// The offset of the instrument name.
        static let instrument = 82

        /// The offset of the telescope name.
        static let telescope = 122

        /// The offset of the local start time.
        static let dateTime = 162

        /// The offset of the UTC start time.
        static let dateTimeUTC = 170
    }

    /// The file ID, required to be ``fileIDMarker``.
    ///
    /// A different value is rejected unless
    /// ``SERParsingOptions/allowInvalidFileID`` is set, in which case whatever
    /// the file holds is preserved here.
    public let fileID: String

    /// The Lumenera camera series ID. Unused by the format; defaults to 0.
    public let luID: Int32

    /// The pixel layout of the file's frames.
    public let colorID: SERColorID

    /// Whether 16-bit image data is stored least significant byte first.
    ///
    /// This governs the byte order of the *image data* only. The header's own
    /// integers are little-endian either way.
    public let isLittleEndian: Bool

    /// The width, in pixels, of every frame.
    public let imageWidth: Int32

    /// The height, in pixels, of every frame.
    public let imageHeight: Int32

    /// The true bit depth per pixel per plane, in the range `1...16`.
    ///
    /// A value outside that range is rejected unless
    /// ``SERParsingOptions/allowOutOfRangePixelDepth`` is set.
    public let pixelDepthPerPlane: Int32

    /// The number of image frames the file declares.
    ///
    /// This is what the header claims; whether that many frames are actually
    /// present is decided against the file's length.
    public let frameCount: Int32

    /// The name of the observer.
    public let observer: String

    /// The name of the camera used.
    public let instrument: String

    /// The name of the telescope used.
    public let telescope: String

    /// The local start time of the image stream, in 100 ns ticks since
    /// 0001-01-01 00:00:00.
    ///
    /// A value of zero or less is invalid and means the file carries no
    /// timestamp trailer, which is what ``hasTimestampTrailer`` reports.
    public let dateTime: Int64

    /// The UTC start time of the image stream, in 100 ns ticks since
    /// 0001-01-01 00:00:00.
    public let dateTimeUTC: Int64

    /// The number of bytes a single pixel occupies, across all planes.
    ///
    /// One byte per plane for a depth of 1 to 8, two for 9 to 16. A depth the
    /// specification does not define, admitted only through
    /// ``SERParsingOptions/allowOutOfRangePixelDepth``, has no width of its own
    /// and is forced into one of those two bands: at most 8 reads as one byte
    /// per plane, anything larger as two. The frame geometry derived from such
    /// a header is therefore not trustworthy.
    public let bytesPerPixel: Int

    /// The number of bytes a single frame occupies.
    ///
    /// ``imageWidth`` × ``imageHeight`` × ``bytesPerPixel``, computed with
    /// overflow reporting so a corrupt geometry is rejected at parse time
    /// instead of producing a wrapped size later.
    public let bytesPerFrame: Int

    /// The number of planes a frame stores per pixel.
    public var numberOfPlanes: Int
    {
        self.colorID.numberOfPlanes
    }

    /// The mosaic laid over the sensor, or `nil` when frames are not a mosaic.
    public var bayerPattern: SERBayerPattern?
    {
        self.colorID.bayerPattern
    }

    /// Whether the file carries a trailer of per-frame timestamps.
    ///
    /// The specification ties this to the local start time: a value of zero or
    /// less is invalid and means there is no trailer. Whether the trailer is
    /// really there is confirmed against the file's length.
    public var hasTimestampTrailer: Bool
    {
        self.dateTime > 0
    }

    /// Parses a header from the start of a file's bytes.
    ///
    /// Only the first ``size`` bytes are read, so the whole file's data can be
    /// passed straight in. Offsets are relative to the start of `data`, which
    /// may be a slice.
    ///
    /// - Parameters:
    ///   - data:    The file's bytes, of which at least ``size`` must be present.
    ///   - options: The parsing options to apply.
    /// - Throws: ``SERError/invalidHeaderData(reason:)`` if the data is too
    ///           short, if a field fails validation that no leniency flag
    ///           covers, or if the geometry overflows;
    ///           ``SERError/unsupportedColorID(colorID:)`` for an undefined
    ///           color ID without
    ///           ``SERParsingOptions/allowUnknownColorID``;
    ///           ``SERError/unsupportedPixelDepth(depth:)`` for a depth outside
    ///           `1...16` without
    ///           ``SERParsingOptions/allowOutOfRangePixelDepth``; or
    ///           ``SERError/dataError(reason:)`` from the underlying reads.
    public init( data: Data, options: SERParsingOptions ) throws
    {
        guard data.count >= SERHeader.size
        else
        {
            throw SERError.invalidHeaderData( reason: "A SER header is \( SERHeader.size ) bytes, found \( data.count )" )
        }

        let fileID = try SERHeader.text( in: data, at: Offset.fileID, length: SERHeader.fileIDLength )

        if fileID != SERHeader.fileIDMarker, options.contains( .allowInvalidFileID ) == false
        {
            throw SERError.invalidHeaderData( reason: "Invalid file ID: expected \"\( SERHeader.fileIDMarker )\", found \"\( fileID )\"" )
        }

        let luID               = try data.integer( Int32.self, at: Offset.luID,               littleEndian: true )
        let rawColorID         = try data.integer( Int32.self, at: Offset.colorID,            littleEndian: true )
        let littleEndian       = try data.integer( Int32.self, at: Offset.littleEndian,       littleEndian: true )
        let imageWidth         = try data.integer( Int32.self, at: Offset.imageWidth,         littleEndian: true )
        let imageHeight        = try data.integer( Int32.self, at: Offset.imageHeight,        littleEndian: true )
        let pixelDepthPerPlane = try data.integer( Int32.self, at: Offset.pixelDepthPerPlane, littleEndian: true )
        let frameCount         = try data.integer( Int32.self, at: Offset.frameCount,         littleEndian: true )
        let dateTime           = try data.integer( Int64.self, at: Offset.dateTime,           littleEndian: true )
        let dateTimeUTC        = try data.integer( Int64.self, at: Offset.dateTimeUTC,        littleEndian: true )
        let colorID            = SERColorID( rawValue: rawColorID )

        if case .unknown = colorID, options.contains( .allowUnknownColorID ) == false
        {
            throw SERError.unsupportedColorID( colorID: rawColorID )
        }

        // A frame with no extent has no meaningful interpretation: every derived
        // size would be zero or negative. There is nothing to be lenient about,
        // so this is rejected whatever the options say.
        guard imageWidth > 0, imageHeight > 0
        else
        {
            throw SERError.invalidHeaderData( reason: "Invalid image geometry: \( imageWidth )x\( imageHeight )" )
        }

        // Likewise a negative frame count: it cannot be clamped to the frames
        // the file holds, only rejected.
        guard frameCount >= 0
        else
        {
            throw SERError.invalidHeaderData( reason: "Negative frame count: \( frameCount )" )
        }

        if ( 1 ... 16 ).contains( pixelDepthPerPlane ) == false, options.contains( .allowOutOfRangePixelDepth ) == false
        {
            throw SERError.unsupportedPixelDepth( depth: pixelDepthPerPlane )
        }

        let bytesPerPixel                 = ( pixelDepthPerPlane <= 8 ? 1 : 2 ) * colorID.numberOfPlanes
        let ( pixelCount, pixelOverflow ) = Int( imageWidth ).multipliedReportingOverflow( by: Int( imageHeight ) )

        // Two positive `Int32` values cannot overflow a 64-bit `Int`, so this
        // guard only ever fires where `Int` is 32 bits wide.
        guard pixelOverflow == false
        else
        {
            throw SERError.invalidHeaderData( reason: "Image geometry overflows: \( imageWidth )x\( imageHeight )" )
        }

        let ( bytesPerFrame, frameOverflow ) = pixelCount.multipliedReportingOverflow( by: bytesPerPixel )

        guard frameOverflow == false
        else
        {
            throw SERError.invalidHeaderData( reason: "Frame size overflows: \( pixelCount ) pixels of \( bytesPerPixel ) bytes" )
        }

        self.fileID             = fileID
        self.luID               = luID
        self.colorID            = colorID
        self.isLittleEndian     = littleEndian != 0
        self.imageWidth         = imageWidth
        self.imageHeight        = imageHeight
        self.pixelDepthPerPlane = pixelDepthPerPlane
        self.frameCount         = frameCount
        self.dateTime           = dateTime
        self.dateTimeUTC        = dateTimeUTC
        self.bytesPerPixel      = bytesPerPixel
        self.bytesPerFrame      = bytesPerFrame
        self.observer           = try SERHeader.name( in: data, at: Offset.observer,   field: "observer",   options: options )
        self.instrument         = try SERHeader.name( in: data, at: Offset.instrument, field: "instrument", options: options )
        self.telescope          = try SERHeader.name( in: data, at: Offset.telescope,  field: "telescope",  options: options )
    }

    /// Reads the content bytes of a fixed-width text field.
    ///
    /// Unused characters are filled with `0`, so the first NUL byte ends the
    /// text and everything from there on is padding.
    ///
    /// - Parameters:
    ///   - data:   The header bytes.
    ///   - offset: The field's offset within `data`.
    ///   - length: The field's fixed width, in bytes.
    /// - Returns: The bytes preceding the first NUL, which may be none.
    /// - Throws: ``SERError/dataError(reason:)`` if the field is not entirely
    ///           within `data`.
    private static func contentBytes( in data: Data, at offset: Int, length: Int ) throws -> [ UInt8 ]
    {
        let field = try data.slice( at: offset, count: length )

        return Array( field.prefix { $0 != 0 } )
    }

    /// Decodes a fixed-width text field, without validating its characters.
    ///
    /// Bytes that do not form valid UTF-8 — which only a leniency flag lets
    /// through — decode to the replacement character, so the field's original
    /// bytes cannot be recovered from the returned text.
    ///
    /// - Parameters:
    ///   - data:   The header bytes.
    ///   - offset: The field's offset within `data`.
    ///   - length: The field's fixed width, in bytes.
    /// - Returns: The field's text, stripped of its NUL padding.
    /// - Throws: ``SERError/dataError(reason:)`` if the field is not entirely
    ///           within `data`.
    private static func text( in data: Data, at offset: Int, length: Int ) throws -> String
    {
        String( decoding: try SERHeader.contentBytes( in: data, at: offset, length: length ), as: UTF8.self )
    }

    /// Decodes one of the three name fields, validating its characters.
    ///
    /// The specification restricts these fields to printable ASCII
    /// (`0x20...0x7E`). Only the content bytes are checked, since anything
    /// after the first NUL is padding. Validation runs on the raw bytes, before
    /// decoding; text admitted by ``SERParsingOptions/allowNonPrintableStrings``
    /// that is not valid UTF-8 decodes to the replacement character, so those
    /// bytes cannot be recovered from the returned text.
    ///
    /// - Parameters:
    ///   - data:    The header bytes.
    ///   - offset:  The field's offset within `data`.
    ///   - field:   The field's name, used in the error message.
    ///   - options: The parsing options to apply.
    /// - Returns: The field's text, stripped of its NUL padding.
    /// - Throws: ``SERError/invalidHeaderData(reason:)`` if the text leaves the
    ///           printable range without
    ///           ``SERParsingOptions/allowNonPrintableStrings``, or
    ///           ``SERError/dataError(reason:)`` if the field is not entirely
    ///           within `data`.
    private static func name( in data: Data, at offset: Int, field: String, options: SERParsingOptions ) throws -> String
    {
        let bytes       = try SERHeader.contentBytes( in: data, at: offset, length: SERHeader.nameLength )
        let isPrintable = bytes.allSatisfy { $0 >= 0x20 && $0 <= 0x7E }

        if isPrintable == false, options.contains( .allowNonPrintableStrings ) == false
        {
            throw SERError.invalidHeaderData( reason: "The \( field ) field leaves the printable ASCII range" )
        }

        return String( decoding: bytes, as: UTF8.self )
    }

    /// A multi-line, human-readable summary of the header.
    public var description: String
    {
        """
        SERHeader
        {
            File ID:               \( self.fileID )
            LU ID:                 \( self.luID )
            Color ID:              \( self.colorID )
            Image Data Byte Order: \( self.isLittleEndian ? "Little-endian" : "Big-endian" )
            Image Width:           \( self.imageWidth )
            Image Height:          \( self.imageHeight )
            Pixel Depth Per Plane: \( self.pixelDepthPerPlane )
            Frame Count:           \( self.frameCount )
            Observer:              \( self.observer )
            Instrument:            \( self.instrument )
            Telescope:             \( self.telescope )
            Start Time:            \( self.dateTime )
            Start Time UTC:        \( self.dateTimeUTC )
            Number Of Planes:      \( self.numberOfPlanes )
            Bytes Per Pixel:       \( self.bytesPerPixel )
            Bytes Per Frame:       \( self.bytesPerFrame )
            Timestamp Trailer:     \( self.hasTimestampTrailer ? "Yes" : "No" )
        }
        """
    }
}
