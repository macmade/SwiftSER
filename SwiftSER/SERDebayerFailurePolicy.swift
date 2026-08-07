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

/// What SwiftSER does when a consumer's ``SERDebayering`` fails.
///
/// This governs a delegate that *tried* and could not finish. A delegate that
/// declines a pattern through ``SERDebayering/supports(pattern:)`` is not
/// failing — declining is part of the protocol, and SwiftSER always falls back
/// to its own implementation for a pattern nobody claims, whatever this policy
/// says.
///
/// Set on ``SERFile/debayerFailurePolicy``.
public enum SERDebayerFailurePolicy: Sendable, Equatable, CustomStringConvertible
{
    /// Debayer with SwiftSER's own ``SERBilinearDebayering`` instead.
    ///
    /// The default, and what makes the delegation hook safe to install: a
    /// consumer's implementation failing on one file costs image quality, not
    /// the image. The error it raised is not reported.
    case fallBackToBuiltIn

    /// Report the delegate's error to the caller.
    ///
    /// For a consumer whose own implementation failing is a bug it wants to
    /// hear about rather than have papered over.
    case propagate

    /// A human-readable description of the policy.
    public var description: String
    {
        switch self
        {
            case .fallBackToBuiltIn: return "Fall back to the built-in implementation"
            case .propagate:         return "Propagate the error"
        }
    }
}
