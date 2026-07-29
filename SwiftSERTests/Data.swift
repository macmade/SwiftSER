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

struct Test_Data
{
    @Test
    func integerReadsLittleEndian() async throws
    {
        let data = Data( [ 0x01, 0x02, 0x03, 0x04 ] )

        #expect( try data.integer( Int32.self, at: 0, littleEndian: true ) == 0x04030201 )
    }

    @Test
    func integerReadsBigEndian() async throws
    {
        let data = Data( [ 0x01, 0x02, 0x03, 0x04 ] )

        #expect( try data.integer( Int32.self, at: 0, littleEndian: false ) == 0x01020304 )
    }

    @Test
    func integerReadsAtOffset() async throws
    {
        let data = Data( [ 0xFF, 0xFF, 0x01, 0x02, 0x03, 0x04 ] )

        #expect( try data.integer( Int32.self, at: 2, littleEndian: true )  == 0x04030201 )
        #expect( try data.integer( Int32.self, at: 2, littleEndian: false ) == 0x01020304 )
    }

    @Test
    func integerReadsEveryWidth() async throws
    {
        let data = Data( [ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 ] )

        #expect( try data.integer( UInt8.self,  at: 0, littleEndian: true )  == 0x01 )
        #expect( try data.integer( UInt16.self, at: 0, littleEndian: true )  == 0x0201 )
        #expect( try data.integer( UInt16.self, at: 0, littleEndian: false ) == 0x0102 )
        #expect( try data.integer( Int64.self,  at: 0, littleEndian: true )  == 0x0807060504030201 )
        #expect( try data.integer( Int64.self,  at: 0, littleEndian: false ) == 0x0102030405060708 )
    }

    @Test
    func integerPreservesTheSignBit() async throws
    {
        // A header field whose high bit is set must decode to a negative
        // `Int32`, not trap and not saturate.
        let data = Data( [ 0x00, 0x00, 0x00, 0x80 ] )

        #expect( try data.integer( Int32.self, at: 0, littleEndian: true )  == Int32.min )
        #expect( try data.integer( Int32.self, at: 0, littleEndian: false ) == 0x00000080 )
    }

    @Test
    func integerDecodesUnsignedValuesAboveTheSignedRange() async throws
    {
        // 16-bit SER samples are unsigned: a value above 32767 must not come
        // back negative.
        let data = Data( [ 0xFF, 0xFF ] )

        #expect( try data.integer( UInt16.self, at: 0, littleEndian: true ) == 65535 )
        #expect( try data.integer( Int16.self,  at: 0, littleEndian: true ) == -1 )
    }

    @Test
    func integerHonorsTheSliceBase() async throws
    {
        // A slice of a larger buffer does not start at index zero. Offsets are
        // relative to the slice, never to the buffer it came from.
        let full  = Data( [ 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x02, 0x03, 0x04 ] )
        let slice = full[ 4 ..< 8 ]

        #expect( try slice.integer( Int32.self, at: 0, littleEndian: true ) == 0x04030201 )
    }

    @Test
    func integerThrowsWhenOutOfBounds() async throws
    {
        let data = Data( [ 0x01, 0x02, 0x03, 0x04 ] )

        try #require( throws: SERError.self ) { try data.integer( Int32.self, at:  1, littleEndian: true ) }
        try #require( throws: SERError.self ) { try data.integer( Int64.self, at:  0, littleEndian: true ) }
        try #require( throws: SERError.self ) { try data.integer( Int32.self, at: -1, littleEndian: true ) }
    }

    @Test
    func sliceReturnsTheRequestedBytes() async throws
    {
        let data = Data( ( 0 ..< 16 ).map { UInt8( $0 ) } )

        #expect( try Array( data.slice( at:  4, count: 4 ) ) == [ 4, 5, 6, 7 ] )
        #expect( try Array( data.slice( at:  0, count: 0 ) ) == [] )
        #expect( try Array( data.slice( at: 16, count: 0 ) ) == [] )
    }

    @Test
    func sliceHonorsTheSliceBase() async throws
    {
        // Same rule as `integer(_:at:littleEndian:)`: a non-zero-based slice
        // must not shift the meaning of an offset.
        let full  = Data( ( 0 ..< 16 ).map { UInt8( $0 ) } )
        let slice = full[ 8 ..< 16 ]

        #expect( try Array( slice.slice( at: 0, count: 4 ) ) == [ 8, 9, 10, 11 ] )
        #expect( try Array( slice.slice( at: 4, count: 4 ) ) == [ 12, 13, 14, 15 ] )
    }

    @Test
    func sliceKeepsTheReceiverIndices() async throws
    {
        // The result shares the receiver's storage instead of copying, so its
        // indices are the ones it occupies in the receiver. Subscripting it
        // from zero would trap, which is why this contract is pinned here
        // rather than left to be rediscovered.
        let data   = Data( ( 0 ..< 16 ).map { UInt8( $0 ) } )
        let result = try data.slice( at: 4, count: 4 )

        #expect( result.startIndex == data.startIndex + 4 )
        #expect( result.endIndex   == data.startIndex + 8 )
        #expect( result[ result.startIndex ] == 4 )
    }

    @Test
    func sliceThrowsWhenOutOfBounds() async throws
    {
        let data = Data( ( 0 ..< 16 ).map { UInt8( $0 ) } )

        try #require( throws: SERError.self ) { try data.slice( at: 16, count:  1 ) }
        try #require( throws: SERError.self ) { try data.slice( at: 12, count:  8 ) }
        try #require( throws: SERError.self ) { try data.slice( at: -1, count:  4 ) }
        try #require( throws: SERError.self ) { try data.slice( at:  0, count: -1 ) }
    }

    @Test
    func sliceThrowsRatherThanOverflowing() async throws
    {
        // `offset + count` must not be allowed to wrap around into a range that
        // looks valid.
        let data = Data( ( 0 ..< 16 ).map { UInt8( $0 ) } )

        try #require( throws: SERError.self ) { try data.slice( at: 1, count: Int.max ) }
        try #require( throws: SERError.self ) { try data.slice( at: Int.max, count: 1 ) }
    }
}
