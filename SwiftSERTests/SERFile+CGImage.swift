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

#if canImport( CoreGraphics )

import CoreGraphics
import Foundation
@testable import SwiftSER
import Testing

struct Test_SERFile_CGImage
{
    // MARK: - Mosaic files

    @Test
    func rendersAMosaicFrameAsAThreeChannelImage() async throws
    {
        // A 2×2 RGGB mosaic of `1 2 / 3 4`, which is one whole tile. The
        // debayered values are the built-in implementation's own hand-computed
        // expectation, and the halves round away from zero.
        let file  = try Self.mosaicFile( colorID: 8 )
        let image = try file.cgImage( ofFrame: 0, scaled: false )

        #expect( image.width                          == 2 )
        #expect( image.height                         == 2 )
        #expect( image.bitsPerComponent               == 8 )
        #expect( image.bitsPerPixel                   == 24 )
        #expect( image.bytesPerRow                    == 6 )
        #expect( image.colorSpace?.numberOfComponents == 3 )

        #expect( try Self.componentBytes( of: image ) == [
            1, 3, 4,
            1, 2, 4,
            1, 3, 4,
            1, 3, 4,
        ] )
    }

    @Test
    func everyMosaicColorIDRendersInThreeChannels() async throws
    {
        try Test_SERFile.bayerColorIDs.forEach
        {
            let image = try Test_SERFile.fileDeclaring( colorID: $0.colorID ).cgImage( ofFrame: 0, scaled: false )

            #expect( image.bitsPerPixel                   == 24, "color ID \( $0.colorID ) renders at the wrong depth" )
            #expect( image.colorSpace?.numberOfComponents == 3,  "color ID \( $0.colorID ) renders in the wrong space" )
            #expect( image.width                          == 4 )
            #expect( image.height                         == 4 )
        }
    }

    @Test
    func rendersAMosaicThroughTheInstalledDebayering() async throws
    {
        // The image is produced from `debayeredSamples(ofFrame:)`, so whichever
        // implementation answers for the pattern is the one the pixels come
        // from.
        let file     = try Self.mosaicFile( colorID: 8 )
        let delegate = Test_SERFile.Delegate( accepts: true, output: { width, height in ( 0 ..< width * height * 3 ).map { Double( $0 * 10 ) } } )

        file.debayering = delegate

        let image = try file.cgImage( ofFrame: 0, scaled: false )

        #expect( delegate.calls.count                 == 1 )
        #expect( try Self.componentBytes( of: image ) == [ 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110 ] )
    }

    // MARK: - Files that carry no mosaic

    @Test
    func rendersAFrameThatIsNotAMosaicInItsOwnPlanes() async throws
    {
        try Test_SERFile.plainColorIDs.forEach
        {
            let image = try Test_SERFile.fileDeclaring( colorID: $0.colorID ).cgImage( ofFrame: 0, scaled: false )

            #expect( image.colorSpace?.numberOfComponents == $0.planes,     "color ID \( $0.colorID ) renders in the wrong space" )
            #expect( image.bitsPerPixel                   == 8 * $0.planes, "color ID \( $0.colorID ) renders at the wrong depth" )
        }
    }

    @Test
    func aMonoFrameRendersTheSameThroughEitherEntryPoint() async throws
    {
        // Nothing to resolve means the file's convenience and the frame's own
        // image are the same picture.
        let file = try Test_SERFile.fileDeclaring( colorID: 0 )

        #expect( try Self.componentBytes( of: file.cgImage( ofFrame: 0, scaled: true ) ) == ( try Self.componentBytes( of: file.frame( at: 0 ).cgImage( scaled: true ) ) ) )
    }

    // MARK: - Range scaling

    @Test
    func scalesTheFramesSamplesToFullRange() async throws
    {
        // A 12-bit capture stops at 4095 of 65535 and renders at 6% brightness
        // unless it is scaled, which is what the option is for.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.littleEndian       = 1
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 12
        fields.frameCount         = 1

        let data = TestUtilities.File( header: fields, frames: [ [ 0xFF, 0x0F, 0x55, 0x05 ] ], timestamps: nil ).data
        let file = try SERFile( data: data, options: .strict )

        #expect( try Self.componentWords( of: file.cgImage( ofFrame: 0, scaled: true  ) ) == [ 65535, 21845 ] )
        #expect( try Self.componentWords( of: file.cgImage( ofFrame: 0, scaled: false ) ) == [  4095,  1365 ] )
    }

    @Test
    func scalesEveryChannelOfAThreeChannelFrame() async throws
    {
        // Scaling is per sample, so a color frame's three channels are each
        // stretched by the same factor rather than one of them being missed.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 100
        fields.littleEndian       = 1
        fields.imageWidth         = 1
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 12
        fields.frameCount         = 1

        let frame = [ UInt8 ]( [ 0xFF, 0x0F, 0x55, 0x05, 0x33, 0x03 ] )
        let data  = TestUtilities.File( header: fields, frames: [ frame ], timestamps: nil ).data
        let file  = try SERFile( data: data, options: .strict )

        #expect( try Self.componentWords( of: file.cgImage( ofFrame: 0, scaled: true  ) ) == [ 65535, 21845, 13107 ] )
        #expect( try Self.componentWords( of: file.cgImage( ofFrame: 0, scaled: false ) ) == [  4095,  1365,   819 ] )
    }

    // MARK: - Failure paths

    @Test
    func rejectsAnImageRequestForAnOutOfRangeFrame() async throws
    {
        let file = try Test_SERFile.fileDeclaring( colorID: 0 )

        #expect( throws: SERError.self )
        {
            try file.cgImage( ofFrame: 1, scaled: true )
        }

        #expect( throws: SERError.self )
        {
            try file.cgImage( ofFrame: -1, scaled: true )
        }
    }

    @Test
    func reportsADebayeringFailureUnderThePropagatePolicy() async throws
    {
        let file = try Self.mosaicFile( colorID: 8 )

        file.debayering           = Test_SERFile.Delegate( accepts: true, output: nil )
        file.debayerFailurePolicy = .propagate

        #expect( throws: Test_SERFile.DelegateError.self )
        {
            try file.cgImage( ofFrame: 0, scaled: true )
        }
    }

    // MARK: - Helpers

    /// A one-frame 2×2 8-bit mosaic file holding `1 2 / 3 4`.
    ///
    /// A 2×2 mosaic is exactly one tile, so every site carries a different
    /// filter and the debayered result follows from the tile alone.
    ///
    /// - Parameter colorID: The raw color ID the header declares.
    /// - Returns: The parsed file.
    /// - Throws: Any error raised while parsing.
    private static func mosaicFile( colorID: Int32 ) throws -> SERFile
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = colorID
        fields.imageWidth         = 2
        fields.imageHeight        = 2
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        return try SERFile( data: TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4 ] ], timestamps: nil ).data, options: .strict )
    }

    /// The bytes an image's data provider holds.
    ///
    /// - Parameter image: The image to read.
    /// - Returns: The pixel bytes, exactly as the image was given them.
    /// - Throws: An expectation failure if the image carries no provider data.
    private static func componentBytes( of image: CGImage ) throws -> [ UInt8 ]
    {
        Array( try #require( image.dataProvider?.data as Data? ) )
    }

    /// The 16-bit components an image's data provider holds, in host order.
    ///
    /// Read through `loadUnaligned`, as ``SERFrame`` reads a frame's own
    /// containers and for the same reason: a `Data` gives out no alignment
    /// guarantee, and binding its bytes to `UInt16` would assume one.
    ///
    /// - Parameter image: The image to read.
    /// - Returns: The pixel components, exactly as the image was given them.
    /// - Throws: An expectation failure if the image carries no provider data.
    private static func componentWords( of image: CGImage ) throws -> [ UInt16 ]
    {
        try #require( image.dataProvider?.data as Data? ).withUnsafeBytes
        {
            bytes in

            stride( from: 0, to: bytes.count - ( bytes.count % 2 ), by: 2 ).map
            {
                bytes.loadUnaligned( fromByteOffset: $0, as: UInt16.self )
            }
        }
    }
}

#endif
