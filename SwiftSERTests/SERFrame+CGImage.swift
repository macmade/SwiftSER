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
import ImageIO
@testable import SwiftSER
import Testing
import UniformTypeIdentifiers

struct Test_SERFrame_CGImage
{
    /// Each depth boundary, the bytes storing its largest conforming value, and
    /// the component that value renders to with scaling on and off.
    ///
    /// Hand-computed from the specification's alignment rules. A depth of 1 to 8
    /// is MSB-aligned in a byte and renders to eight bits per component; a depth
    /// of 9 to 16 is LSB-aligned in two bytes and renders to sixteen. Scaling
    /// takes the largest conforming value to full scale in every row, which is
    /// the whole point of it — a 12-bit capture is otherwise displayed at 6%
    /// brightness. Unscaled, the stored value is handed over as it is.
    static let depths: [ ( depth: Int32, stored: [ UInt8 ], bitsPerComponent: Int, scaled: Int, unscaled: Int ) ] = [
        (  1, [ 0x80 ],        8,   255,   128 ),
        (  5, [ 0xF8 ],        8,   255,   248 ),
        (  8, [ 0xFF ],        8,   255,   255 ),
        (  9, [ 0xFF, 0x01 ], 16, 65535,   511 ),
        ( 12, [ 0xFF, 0x0F ], 16, 65535,  4095 ),
        ( 16, [ 0xFF, 0xFF ], 16, 65535, 65535 ),
    ]

    /// Scaling a 4-bit frame, whose range of `0...240` divides 255 exactly.
    ///
    /// A 4-bit sample is MSB-aligned, so the stored values are the multiples of
    /// 16 and the scaling factor is `255 / 240`, or `1.0625` — which every row
    /// below is chosen to be an exact multiple of, so that no expectation
    /// depends on how a tie rounds. The last row is not a conforming value at
    /// all: it holds the padding bits the specification says are zero, and is
    /// what the clamp exists for.
    static let fourBitScaling: [ ( stored: UInt8, scaled: Int ) ] = [
        ( 0x00,   0 ),
        ( 0x10,  17 ),
        ( 0x50,  85 ),
        ( 0xF0, 255 ),
        ( 0xFF, 255 ),
    ]

    /// Scaling a 12-bit frame, whose range of `0...4095` divides 65535 exactly.
    ///
    /// A 12-bit sample is LSB-aligned, so the stored value is the sample. The
    /// factor is `65535 / 4095`, and each row is a value it takes to a whole
    /// number: 4095 divided by three and by five, and the endpoints.
    static let twelveBitScaling: [ ( stored: [ UInt8 ], scaled: Int ) ] = [
        ( [ 0x00, 0x00 ],     0 ),
        ( [ 0x33, 0x03 ], 13107 ),
        ( [ 0x55, 0x05 ], 21845 ),
        ( [ 0xFF, 0x0F ], 65535 ),
    ]

    @Test
    func everyImageTableIsListed() async throws
    {
        // The tests below iterate these tables, so a row dropped from one would
        // leave them passing while proving less.
        #expect( Self.depths.map           { $0.depth }    == [ 1, 5, 8, 9, 12, 16 ] )
        #expect( Self.depths.map           { $0.scaled }   == [ 255, 255, 255, 65535, 65535, 65535 ] )
        #expect( Self.depths.map           { $0.unscaled } == [ 128, 248, 255, 511, 4095, 65535 ] )
        #expect( Self.fourBitScaling.map   { $0.stored }   == [ 0x00, 0x10, 0x50, 0xF0, 0xFF ] )
        #expect( Self.fourBitScaling.map   { $0.scaled }   == [ 0, 17, 85, 255, 255 ] )
        #expect( Self.twelveBitScaling.map { $0.scaled }   == [ 0, 13107, 21845, 65535 ] )
    }

    // MARK: - Geometry and layout

    @Test
    func rendersAMonoFrameAsASingleChannelImage() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 3
        fields.imageHeight        = 2
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let data  = TestUtilities.File( header: fields, frames: [ [ 10, 20, 30, 40, 50, 60 ] ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )

        #expect( image.width                          == 3 )
        #expect( image.height                         == 2 )
        #expect( image.bitsPerComponent               == 8 )
        #expect( image.bitsPerPixel                   == 8 )
        #expect( image.bytesPerRow                    == 3 )
        #expect( image.alphaInfo                      == .none )
        #expect( image.colorSpace?.numberOfComponents == 1 )

        #expect( try Self.componentBytes( of: image ) == [ 10, 20, 30, 40, 50, 60 ] )
    }

    @Test
    func rendersAnRGBFrameAsAThreeChannelImage() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 100
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let data  = TestUtilities.File( header: fields, frames: [ [ 10, 20, 30, 40, 50, 60 ] ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )

        // Twenty-four bits per pixel is not one of the layouts a bitmap
        // *context* accepts, but `CGImageCreate` does take it, which is what
        // lets three planes be handed over without an alpha channel invented to
        // pad them.
        #expect( image.width                          == 2 )
        #expect( image.height                         == 1 )
        #expect( image.bitsPerComponent               == 8 )
        #expect( image.bitsPerPixel                   == 24 )
        #expect( image.bytesPerRow                    == 6 )
        #expect( image.alphaInfo                      == .none )
        #expect( image.colorSpace?.numberOfComponents == 3 )

        #expect( try Self.componentBytes( of: image ) == [ 10, 20, 30, 40, 50, 60 ] )
    }

    @Test
    func rendersABGRFrameInTheChannelOrderTheSamplesCarry() async throws
    {
        // The image follows `samples`, which reorders BGR to RGB on decode, and
        // not the bytes the file stores.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 101
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let data  = TestUtilities.File( header: fields, frames: [ [ 10, 20, 30, 40, 50, 60 ] ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )

        #expect( try Self.componentBytes( of: image ) == [ 30, 20, 10, 60, 50, 40 ] )
    }

    @Test
    func rendersAMosaicFrameAsItsUndebayeredPlane() async throws
    {
        // A frame knows nothing of the file's debayering, so its own image is
        // the mosaic as a single gray plane. `SERFile/cgImage(ofFrame:scaled:)`
        // is the one that resolves it.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 8
        fields.imageWidth         = 2
        fields.imageHeight        = 2
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let data  = TestUtilities.File( header: fields, frames: [ [ 1, 2, 3, 4 ] ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )

        #expect( image.bitsPerPixel                   == 8 )
        #expect( image.colorSpace?.numberOfComponents == 1 )
        #expect( try Self.componentBytes( of: image ) == [ 1, 2, 3, 4 ] )
    }

    @Test
    func rendersASixteenBitFrameAtSixteenBitsPerComponent() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.littleEndian       = 1
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = 1

        let data  = TestUtilities.File( header: fields, frames: [ [ 0x34, 0x12, 0x78, 0x56 ] ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )

        #expect( image.bitsPerComponent == 16 )
        #expect( image.bitsPerPixel     == 16 )
        #expect( image.bytesPerRow      == 4 )

        // Read back as host-order words, which is what the image declares.
        #expect( try Self.componentWords( of: image ) == [ 0x1234, 0x5678 ] )
    }

    @Test
    func rendersASixteenBitColorFrameAtFortyEightBitsPerPixel() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 100
        fields.littleEndian       = 1
        fields.imageWidth         = 1
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = 1

        let data  = TestUtilities.File( header: fields, frames: [ [ 0x01, 0x00, 0x02, 0x00, 0x03, 0x00 ] ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )

        #expect( image.bitsPerComponent               == 16 )
        #expect( image.bitsPerPixel                   == 48 )
        #expect( image.bytesPerRow                    == 6 )
        #expect( image.colorSpace?.numberOfComponents == 3 )

        #expect( try Self.componentWords( of: image ) == [ 1, 2, 3 ] )
    }

    @Test
    func rendersTheByteOrderTheImageDeclares() async throws
    {
        // The two byte orders a file can store 16-bit data in are resolved by
        // the decode, so both render to the same words — the image never
        // inherits the file's byte order.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 1
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = 1
        fields.littleEndian       = 1

        let little = TestUtilities.File( header: fields, frames: [ [ 0x34, 0x12 ] ], timestamps: nil ).data

        fields.littleEndian = 0

        let big = TestUtilities.File( header: fields, frames: [ [ 0x12, 0x34 ] ], timestamps: nil ).data

        #expect( try Self.componentWords( of: SERFile( data: little, options: .strict ).frame( at: 0 ).cgImage( scaled: false ) ) == [ 0x1234 ] )
        #expect( try Self.componentWords( of: SERFile( data: big,    options: .strict ).frame( at: 0 ).cgImage( scaled: false ) ) == [ 0x1234 ] )
    }

    // MARK: - Range scaling

    @Test
    func scalingTakesEveryDepthsLargestValueToFullScale() async throws
    {
        try Self.depths.forEach
        {
            let image = try Self.image( depth: $0.depth, stored: $0.stored, scaled: true )

            #expect( image.bitsPerComponent == $0.bitsPerComponent, "depth \( $0.depth ) renders at the wrong component width" )

            let components = $0.bitsPerComponent == 8 ? try Self.componentBytes( of: image ).map { Int( $0 ) } : try Self.componentWords( of: image ).map { Int( $0 ) }

            #expect( components == [ $0.scaled ], "depth \( $0.depth ) scales wrongly" )
        }
    }

    @Test
    func withoutScalingEveryDepthKeepsItsStoredValue() async throws
    {
        try Self.depths.forEach
        {
            let image      = try Self.image( depth: $0.depth, stored: $0.stored, scaled: false )
            let components = $0.bitsPerComponent == 8 ? try Self.componentBytes( of: image ).map { Int( $0 ) } : try Self.componentWords( of: image ).map { Int( $0 ) }

            #expect( components == [ $0.unscaled ], "depth \( $0.depth ) is altered where it should not be" )
        }
    }

    @Test
    func scalesAnEightBitDepthAcrossItsWholeRange() async throws
    {
        try Self.fourBitScaling.forEach
        {
            let image = try Self.image( depth: 4, stored: [ $0.stored ], scaled: true )

            // Compared as `Int` rather than by converting the table's value to
            // the component's own type: a mistyped row would then trap inside
            // the initializer and take the whole run down with it, reporting
            // nothing for any other test.
            #expect( try Self.componentBytes( of: image ).map { Int( $0 ) } == [ $0.scaled ], "\( $0.stored ) scales wrongly at depth 4" )
        }
    }

    @Test
    func scalesASixteenBitDepthAcrossItsWholeRange() async throws
    {
        try Self.twelveBitScaling.forEach
        {
            let image = try Self.image( depth: 12, stored: $0.stored, scaled: true )

            #expect( try Self.componentWords( of: image ).map { Int( $0 ) } == [ $0.scaled ], "\( $0.stored ) scales wrongly at depth 12" )
        }
    }

    @Test
    func roundsASampleToTheNearestComponent() async throws
    {
        // Samples are `Double` and a component is an integer, so the conversion
        // has to round somewhere. It rounds to the nearest, with halves going
        // away from zero — only reachable through debayering or scaling, since
        // a decoded sample is always whole.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 6
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let header = try SERHeader( data: fields.data, options: .strict )
        let image  = try SERFrame.cgImage( samples: [ 0.4, 0.5, 0.6, 1.5, 2.5, 254.5 ], header: header, planes: 1, scaled: false )

        #expect( try Self.componentBytes( of: image ) == [ 0, 1, 1, 2, 3, 255 ] )
    }

    @Test
    func clampsASampleAboveTheDepthsDeclaredRange() async throws
    {
        // Nothing validates the padding bits a sub-byte depth leaves over, so a
        // sample can exceed `sampleRange`. Scaled, it would land past full
        // scale, and converting that to a component would trap.
        let scaled   = try Self.image( depth: 4, stored: [ 0xFF ], scaled: true )
        let unscaled = try Self.image( depth: 4, stored: [ 0xFF ], scaled: false )

        #expect( try Self.componentBytes( of: scaled )   == [ 255 ] )
        #expect( try Self.componentBytes( of: unscaled ) == [ 255 ] )
    }

    // MARK: - The layout Core Graphics reads

    @Test
    func drawsAnEightBitGrayFrameAtTheRightBrightness() async throws
    {
        // Reading the provider's bytes proves only what was handed in. Drawing
        // is what puts the declared layout — bits per component, bits per pixel
        // and byte order — in front of Core Graphics itself, which is the only
        // thing that can tell a wrong one from a right one.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let data  = TestUtilities.File( header: fields, frames: [ [ 0xFF, 0x00 ] ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )
        let drawn = try Self.drawnPixels( of: image )

        // Asserted as bright and dark rather than as exact values: drawing a
        // device gray image into a device RGB context is a color conversion,
        // and 255 comes back as 254.
        #expect( drawn.count >= 8 )
        #expect( try #require( drawn.first ) > 200 )
        #expect( try #require( drawn.dropFirst( 4 ).first ) < 50 )
    }

    @Test
    func drawsASixteenBitGrayFrameInTheDeclaredByteOrder() async throws
    {
        // The decisive test of the byte order the image declares. The first
        // pixel's word is 0xFF00 and the second's is 0x00FF, so reading them
        // the other way round swaps bright for dark.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.littleEndian       = 1
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = 1

        let data  = TestUtilities.File( header: fields, frames: [ [ 0x00, 0xFF, 0xFF, 0x00 ] ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )
        let drawn = try Self.drawnPixels( of: image )

        #expect( drawn.count >= 8 )
        #expect( try #require( drawn.first ) > 200 )
        #expect( try #require( drawn.dropFirst( 4 ).first ) < 50 )
    }

    @Test
    func drawsATwentyFourBitColorFrameInTheRightChannels() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 100
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let data  = TestUtilities.File( header: fields, frames: [ [ 255, 0, 0, 0, 0, 255 ] ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )

        try Self.expectRedThenBlue( in: image )
    }

    @Test
    func drawsAFortyEightBitColorFrameInTheRightChannels() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 100
        fields.littleEndian       = 1
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 16
        fields.frameCount         = 1

        let frame = [ UInt8 ]( [
            0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF,
        ] )

        let data  = TestUtilities.File( header: fields, frames: [ frame ], timestamps: nil ).data
        let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: false )

        try Self.expectRedThenBlue( in: image )
    }

    @Test
    func everyRenderedLayoutSurvivesAPNGRoundTrip() async throws
    {
        // The other thing a consumer does with the image. A layout Core
        // Graphics tolerates but ImageIO will not encode would pass every
        // assertion above and still be useless.
        try [ ( colorID: Int32( 0 ), depth: Int32( 8 ) ), ( 0, 16 ), ( 100, 8 ), ( 100, 16 ) ].forEach
        {
            var fields = TestUtilities.wellFormedHeader

            fields.colorID            = $0.colorID
            fields.littleEndian       = 1
            fields.imageWidth         = 2
            fields.imageHeight        = 2
            fields.pixelDepthPerPlane = $0.depth
            fields.frameCount         = 1

            let frame = ( 0 ..< fields.bytesPerFrame ).map { UInt8( truncatingIfNeeded: $0 * 7 ) }
            let data  = TestUtilities.File( header: fields, frames: [ frame ], timestamps: nil ).data
            let image = try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: true )
            let read  = try Self.pngRoundTrip( of: image )

            #expect( read?.width  == 2, "color ID \( $0.colorID ) at depth \( $0.depth ) does not survive a PNG round trip" )
            #expect( read?.height == 2, "color ID \( $0.colorID ) at depth \( $0.depth ) does not survive a PNG round trip" )
        }
    }

    // MARK: - Failure paths

    @Test
    func rejectsSamplesThatDoNotFillTheGeometry() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 2
        fields.imageHeight        = 2
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let header = try SERHeader( data: fields.data, options: .strict )

        #expect( throws: SERError.self )
        {
            try SERFrame.cgImage( samples: [ 1, 2, 3 ], header: header, planes: 1, scaled: false )
        }
    }

    @Test
    func rejectsAPlaneCountNoColorSpaceDescribes() async throws
    {
        // One plane is gray and three are RGB; the format defines nothing else,
        // so there is no color space to render two or four planes into.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 2
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let header = try SERHeader( data: fields.data, options: .strict )

        // Asserted on the reason, not merely on the type: Core Graphics refuses
        // a two-plane layout of its own accord, so a guard that let one through
        // would still throw, and only the message tells the two apart.
        #expect
        {
            try SERFrame.cgImage( samples: [ 1, 2, 3, 4 ], header: header, planes: 2, scaled: false )
        }
        throws:
        {
            ( $0 as? SERError )?.errorDescription?.contains( "No color space" ) == true
        }
    }

    @Test
    func rejectsAFrameWhoseBytesAreMissing() async throws
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 4
        fields.imageHeight        = 4
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let header = try SERHeader( data: fields.data, options: .strict )
        let frame  = SERFrame( index: 0, header: header, timestamp: nil, rawData: Data( [ 1, 2, 3 ] ) )

        #expect( throws: SERError.self )
        {
            try frame.cgImage( scaled: true )
        }
    }

    @Test
    func rendersASampleThatNamesNoNumberAsBlack() async throws
    {
        // Only reachable through a consumer's own debayering, whose result the
        // library does not otherwise inspect. Converting a NaN to a component
        // traps, so it has to be answered for here.
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.imageWidth         = 4
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = 8
        fields.frameCount         = 1

        let header = try SERHeader( data: fields.data, options: .strict )
        let image  = try SERFrame.cgImage( samples: [ .nan, .infinity, -.infinity, -1 ], header: header, planes: 1, scaled: true )

        #expect( try Self.componentBytes( of: image ) == [ 0, 255, 0, 0 ] )
    }

    // MARK: - Helpers

    /// Renders a one-sample mono frame of a given depth.
    ///
    /// - Parameters:
    ///   - depth:  The pixel depth per plane to declare.
    ///   - stored: The bytes of the single sample, little-endian.
    ///   - scaled: Whether to scale the sample to the output's full range.
    /// - Returns: The rendered image.
    /// - Throws: Any error raised while building or rendering the file.
    private static func image( depth: Int32, stored: [ UInt8 ], scaled: Bool ) throws -> CGImage
    {
        var fields = TestUtilities.wellFormedHeader

        fields.colorID            = 0
        fields.littleEndian       = 1
        fields.imageWidth         = 1
        fields.imageHeight        = 1
        fields.pixelDepthPerPlane = depth
        fields.frameCount         = 1

        let data = TestUtilities.File( header: fields, frames: [ stored ], timestamps: nil ).data

        return try SERFile( data: data, options: .strict ).frame( at: 0 ).cgImage( scaled: scaled )
    }

    /// The RGBA pixels an image draws to, through Core Graphics itself.
    ///
    /// Every image drawn here is one pixel high, so the flip between Core
    /// Graphics' bottom-left origin and the image's top-left one cannot reorder
    /// anything.
    ///
    /// - Parameter image: The image to draw.
    /// - Returns: Four bytes per pixel, red first.
    /// - Throws: An expectation failure if the context cannot be created or
    ///           carries no pixels.
    private static func drawnPixels( of image: CGImage ) throws -> [ UInt8 ]
    {
        let context = try #require( CGContext(
            data:             nil,
            width:            image.width,
            height:           image.height,
            bitsPerComponent: 8,
            bytesPerRow:      image.width * 4,
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGImageAlphaInfo.premultipliedLast.rawValue
        ) )

        context.draw( image, in: CGRect( x: 0, y: 0, width: image.width, height: image.height ) )

        let pixels = try #require( context.data )

        return Array( UnsafeRawBufferPointer( start: pixels, count: image.width * image.height * 4 ) )
    }

    /// Asserts that a two-pixel image draws as a red pixel then a blue one.
    ///
    /// - Parameter image: The image to draw.
    /// - Throws: An expectation failure if the image cannot be drawn.
    private static func expectRedThenBlue( in image: CGImage ) throws
    {
        let drawn = try Self.drawnPixels( of: image )

        #expect( drawn.count >= 8 )

        let first = Array( drawn.prefix( 3 ) )
        let last  = Array( drawn.dropFirst( 4 ).prefix( 3 ) )

        #expect( try #require( first.first ) > 200 )
        #expect( try #require( first.last )  < 50 )
        #expect( try #require( last.first )  < 50 )
        #expect( try #require( last.last )   > 200 )
    }

    /// Encodes an image to PNG and reads it back.
    ///
    /// - Parameter image: The image to encode.
    /// - Returns: The decoded image, or `nil` if either step declined it.
    /// - Throws: An expectation failure if the destination cannot be created.
    private static func pngRoundTrip( of image: CGImage ) throws -> CGImage?
    {
        let encoded = NSMutableData()

        let destination = try #require( CGImageDestinationCreateWithData( encoded, UTType.png.identifier as CFString, 1, nil ) )

        CGImageDestinationAddImage( destination, image, nil )

        guard CGImageDestinationFinalize( destination ), let source = CGImageSourceCreateWithData( encoded, nil )
        else
        {
            return nil
        }

        return CGImageSourceCreateImageAtIndex( source, 0, nil )
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
