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

struct Test_SERDebayerFailurePolicy
{
    /// Every policy, with the name it describes itself by.
    static let policies: [ ( policy: SERDebayerFailurePolicy, name: String ) ] = [
        ( .fallBackToBuiltIn, "Fall back to the built-in implementation" ),
        ( .propagate,         "Propagate the error" ),
    ]

    @Test
    func tableCoversEveryPolicy() async throws
    {
        // The tests below iterate the table, so a row dropped from it would
        // leave them passing while proving less.
        #expect( Self.policies.map { $0.name } == [ "Fall back to the built-in implementation", "Propagate the error" ] )
    }

    @Test
    func describesItself() async throws
    {
        Self.policies.forEach
        {
            #expect( $0.policy.description == $0.name )
        }
    }

    @Test
    func theTwoPoliciesAreDistinct() async throws
    {
        // They are compared, not just stored, so they have to tell each other
        // apart.
        #expect( SERDebayerFailurePolicy.fallBackToBuiltIn == SERDebayerFailurePolicy.fallBackToBuiltIn )
        #expect( SERDebayerFailurePolicy.propagate         == SERDebayerFailurePolicy.propagate )
        #expect( SERDebayerFailurePolicy.fallBackToBuiltIn != SERDebayerFailurePolicy.propagate )
    }
}
