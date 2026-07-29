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

struct Test_SERError
{
    @Test
    func description() async throws
    {
        [
            ( error: SERError.invalidFileURL(        url: URL( fileURLWithPath: "/foo/bar.ser" ) ), contains: "/foo/bar.ser" ),
            ( error: SERError.cannotReadFile(        url: URL( fileURLWithPath: "/foo/bar.ser" ) ), contains: "/foo/bar.ser" ),
            ( error: SERError.invalidHeaderData(     reason: "This is a test" ),                    contains: "This is a test" ),
            ( error: SERError.invalidFrameData(      reason: "This is a test" ),                    contains: "This is a test" ),
            ( error: SERError.invalidTrailerData(    reason: "This is a test" ),                    contains: "This is a test" ),
            ( error: SERError.frameIndexOutOfRange(  index: 42, count: 10 ),                        contains: "42" ),
            ( error: SERError.unsupportedColorID(    colorID: 77 ),                                 contains: "77" ),
            ( error: SERError.unsupportedPixelDepth( depth: 24 ),                                   contains: "24" ),
            ( error: SERError.dataError(             reason: "This is a test" ),                    contains: "This is a test" ),
            ( error: SERError.debayerError(          reason: "This is a test" ),                    contains: "This is a test" ),
            ( error: SERError.imageCreationFailed(   reason: "This is a test" ),                    contains: "This is a test" ),
            ( error: SERError.movieExportFailed(     reason: "This is a test" ),                    contains: "This is a test" ),
        ]
        .forEach
        {
            #expect( $0.error.description.isEmpty == false )
            #expect( $0.error.description         != _typeName( SERError.self, qualified: true ) )
            #expect( $0.error.description.contains( $0.contains ) )
        }
    }

    @Test
    func descriptionIsPrefixed() async throws
    {
        // Every error renders through the same `SER Error:` prefix, so callers
        // can recognize the library's errors in a log.
        #expect( SERError.dataError( reason: "This is a test" ).description == "SER Error: Data error: This is a test" )
    }

    @Test
    func errorDescriptionIsNotNil() async throws
    {
        // `LocalizedError` conformance is what makes `localizedDescription`
        // useful; an unimplemented case would silently fall back to the type
        // name instead.
        #expect( SERError.dataError( reason: "This is a test" ).errorDescription != nil )
    }

    @Test
    func frameIndexOutOfRangeReportsIndexAndCount() async throws
    {
        let description = SERError.frameIndexOutOfRange( index: 42, count: 10 ).description

        #expect( description.contains( "42" ) )
        #expect( description.contains( "10" ) )
    }
}
