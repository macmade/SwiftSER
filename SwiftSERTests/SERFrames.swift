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
@testable import SwiftSER
import Testing

struct Test_SERFrames
{
    /// A three-frame file of two pixels each, whose bytes name their frame.
    static func threeFrames() throws -> SERFile
    {
        var fields = TestUtilities.wellFormedHeader

        fields.imageWidth  = 2
        fields.imageHeight = 1
        fields.frameCount  = 3

        let data = TestUtilities.File( header: fields, frames: [ [ 1, 2 ], [ 3, 4 ], [ 5, 6 ] ], timestamps: nil ).data

        return try SERFile( data: data, options: .strict )
    }

    @Test
    func holdsOneEntryPerFrame() async throws
    {
        let file = try Self.threeFrames()

        #expect( file.frames.count      == 3 )
        #expect( file.frames.startIndex == 0 )
        #expect( file.frames.endIndex   == 3 )
    }

    @Test
    func isEmptyWhenTheFileHasNoFrames() async throws
    {
        let file = try SERFile( data: TestUtilities.wellFormedHeader( frameCount: 0 ).file.data, options: .strict )

        #expect( file.frames.isEmpty )
        #expect( file.frames.count == 0 )
    }

    @Test
    func yieldsFramesInFileOrder() async throws
    {
        let file = try Self.threeFrames()

        #expect( file.frames.map { $0.index } == [ 0, 1, 2 ] )
        #expect( try file.frames.flatMap { try $0.samples } == [ 1, 2, 3, 4, 5, 6 ] )
    }

    @Test
    func addressesFramesInAnyOrder() async throws
    {
        let file  = try Self.threeFrames()
        let last  = try #require( file.frames.last )
        let first = try #require( file.frames.first )

        #expect( try file.frames[ 1 ].samples == [ 3, 4 ] )
        #expect( try last.samples             == [ 5, 6 ] )
        #expect( try first.samples            == [ 1, 2 ] )

        #expect( file.frames.reversed().map { $0.index } == [ 2, 1, 0 ] )
    }

    @Test
    func addressesFramesWithoutCopyingTheFilesBytes() async throws
    {
        // A frame's data is a slice sharing the file's storage, which is what
        // lets a capture larger than memory be enumerated. A copy would rebase
        // the indices to zero.
        let file = try Self.threeFrames()

        #expect( file.frames[ 0 ].rawData.startIndex == SERHeader.size )
        #expect( file.frames[ 2 ].rawData.startIndex == SERHeader.size + 4 )
    }

    @Test
    func describesHowManyFramesItHolds() async throws
    {
        let file  = try Self.threeFrames()
        let one   = try SERFile( data: TestUtilities.wellFormedHeader( frameCount: 1 ).file.data, options: .strict )
        let empty = try SERFile( data: TestUtilities.wellFormedHeader( frameCount: 0 ).file.data, options: .strict )

        #expect( file.frames.description  == "3 frames" )
        #expect( one.frames.description   == "1 frame" )
        #expect( empty.frames.description == "0 frames" )
    }

    @Test
    func reportsTheReconciledFrameCountRatherThanTheDeclaredOne() async throws
    {
        // The header over-declares; the collection follows what the file holds.
        var fields = TestUtilities.wellFormedHeader

        fields.frameCount = 4

        let frames = TestUtilities.indexedFrames( count: 2, bytesPerFrame: fields.bytesPerFrame )
        let data   = TestUtilities.File( header: fields, frames: frames, timestamps: nil ).data
        let file = try SERFile( data: data, options: .lenient )

        #expect( file.header.frameCount == 4 )
        #expect( file.frames.count      == 2 )
    }
}
