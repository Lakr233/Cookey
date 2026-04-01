import Crypto
import Foundation
#if canImport(Security)
import Security
#endif

public enum CryptoBoxError: Error {
    case invalidNonce
    case invalidCiphertext
    case authenticationFailed
    case invalidRecipientPublicKey
    case invalidEphemeralPublicKey
    case randomGenerationFailed
}

public enum XSalsa20Poly1305Box {
    public static func open(ciphertext: Data, nonce: Data, sharedSecret: Data) throws -> Data {
        guard nonce.count == 24 else {
            throw CryptoBoxError.invalidNonce
        }

        guard ciphertext.count >= 16 else {
            throw CryptoBoxError.invalidCiphertext
        }

        let key = hsalsa20(sharedSecret, nonce: Data(repeating: 0, count: 16))
        let tag = Array(ciphertext.prefix(16))
        let body = Array(ciphertext.dropFirst(16))
        let nonceBytes = Array(nonce)

        let subkey = hsalsa20(key, nonce: Data(nonceBytes[0 ..< 16]))
        let streamNonce = Array(nonceBytes[16 ..< 24])
        let polyKey = Array(salsa20Block(key: Array(subkey), nonce: streamNonce, counter: 0).prefix(32))

        let computedTag = poly1305Authenticate(message: body, key: polyKey)
        guard constantTimeEqual(tag, computedTag) else {
            throw CryptoBoxError.authenticationFailed
        }

        let plaintext = salsa20XOR(
            input: body,
            key: Array(subkey),
            nonce: streamNonce,
            initialCounter: 0,
            skip: 32
        )
        return Data(plaintext)
    }

    public static func seal(
        plaintext: Data,
        recipientPublicKey: Data
    ) throws -> (
        ephemeralPublicKey: Data,
        nonce: Data,
        ciphertext: Data
    ) {
        var nonceBytes = [UInt8](repeating: 0, count: 24)
        try fillRandomBytes(&nonceBytes)

        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey: Curve25519.KeyAgreement.PublicKey
        do {
            recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
        } catch {
            throw CryptoBoxError.invalidRecipientPublicKey
        }

        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientKey)
        let sharedKey = sharedSecret.withUnsafeBytes { Data($0) }
        let key = hsalsa20(sharedKey, nonce: Data(repeating: 0, count: 16))
        let subkey = hsalsa20(key, nonce: Data(nonceBytes[0 ..< 16]))
        let streamNonce = Array(nonceBytes[16 ..< 24])
        let body = salsa20XOR(
            input: Array(plaintext),
            key: Array(subkey),
            nonce: streamNonce,
            initialCounter: 0,
            skip: 32
        )
        let polyKey = Array(salsa20Block(key: Array(subkey), nonce: streamNonce, counter: 0).prefix(32))
        let tag = poly1305Authenticate(message: body, key: polyKey)

        return (
            ephemeralPublicKey: ephemeralPrivateKey.publicKey.rawRepresentation,
            nonce: Data(nonceBytes),
            ciphertext: Data(tag + body)
        )
    }

    private static func hsalsa20(_ key: Data, nonce: Data) -> Data {
        let keyBytes = Array(key)
        let nonceBytes = Array(nonce)
        var state = [
            sigma[0], load32(keyBytes, 0), load32(keyBytes, 4), load32(keyBytes, 8),
            load32(keyBytes, 12), sigma[1], load32(nonceBytes, 0), load32(nonceBytes, 4),
            load32(nonceBytes, 8), load32(nonceBytes, 12), sigma[2], load32(keyBytes, 16),
            load32(keyBytes, 20), load32(keyBytes, 24), load32(keyBytes, 28), sigma[3],
        ]

        let working = salsa20Rounds(state)
        var output = [UInt8]()
        output.append(contentsOf: store32(working[0]))
        output.append(contentsOf: store32(working[5]))
        output.append(contentsOf: store32(working[10]))
        output.append(contentsOf: store32(working[15]))
        output.append(contentsOf: store32(working[6]))
        output.append(contentsOf: store32(working[7]))
        output.append(contentsOf: store32(working[8]))
        output.append(contentsOf: store32(working[9]))
        return Data(output)
    }

    private static func salsa20XOR(
        input: [UInt8],
        key: [UInt8],
        nonce: [UInt8],
        initialCounter: UInt64,
        skip: Int
    ) -> [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity(input.count)

        var counter = initialCounter + UInt64(skip / 64)
        var blockOffset = skip % 64
        var index = 0

        while index < input.count {
            let block = salsa20Block(key: key, nonce: nonce, counter: counter)
            let available = min(64 - blockOffset, input.count - index)

            for offset in 0 ..< available {
                output.append(input[index + offset] ^ block[blockOffset + offset])
            }

            index += available
            counter += 1
            blockOffset = 0
        }

        return output
    }

    private static func salsa20Block(key: [UInt8], nonce: [UInt8], counter: UInt64) -> [UInt8] {
        let counterLow = UInt32(counter & 0xffff_ffff)
        let counterHigh = UInt32((counter >> 32) & 0xffff_ffff)
        let state = [
            sigma[0], load32(key, 0), load32(key, 4), load32(key, 8),
            load32(key, 12), sigma[1], load32(nonce, 0), load32(nonce, 4),
            counterLow, counterHigh, sigma[2], load32(key, 16),
            load32(key, 20), load32(key, 24), load32(key, 28), sigma[3],
        ]

        let working = salsa20Rounds(state)
        var output = [UInt8]()
        output.reserveCapacity(64)

        for index in 0 ..< 16 {
            output.append(contentsOf: store32(working[index] &+ state[index]))
        }

        return output
    }

    private static func salsa20Rounds(_ input: [UInt32]) -> [UInt32] {
        var x = input

        for _ in 0 ..< 10 {
            x[4] ^= rotateLeft(x[0] &+ x[12], by: 7)
            x[8] ^= rotateLeft(x[4] &+ x[0], by: 9)
            x[12] ^= rotateLeft(x[8] &+ x[4], by: 13)
            x[0] ^= rotateLeft(x[12] &+ x[8], by: 18)

            x[9] ^= rotateLeft(x[5] &+ x[1], by: 7)
            x[13] ^= rotateLeft(x[9] &+ x[5], by: 9)
            x[1] ^= rotateLeft(x[13] &+ x[9], by: 13)
            x[5] ^= rotateLeft(x[1] &+ x[13], by: 18)

            x[14] ^= rotateLeft(x[10] &+ x[6], by: 7)
            x[2] ^= rotateLeft(x[14] &+ x[10], by: 9)
            x[6] ^= rotateLeft(x[2] &+ x[14], by: 13)
            x[10] ^= rotateLeft(x[6] &+ x[2], by: 18)

            x[3] ^= rotateLeft(x[15] &+ x[11], by: 7)
            x[7] ^= rotateLeft(x[3] &+ x[15], by: 9)
            x[11] ^= rotateLeft(x[7] &+ x[3], by: 13)
            x[15] ^= rotateLeft(x[11] &+ x[7], by: 18)

            x[1] ^= rotateLeft(x[0] &+ x[3], by: 7)
            x[2] ^= rotateLeft(x[1] &+ x[0], by: 9)
            x[3] ^= rotateLeft(x[2] &+ x[1], by: 13)
            x[0] ^= rotateLeft(x[3] &+ x[2], by: 18)

            x[6] ^= rotateLeft(x[5] &+ x[4], by: 7)
            x[7] ^= rotateLeft(x[6] &+ x[5], by: 9)
            x[4] ^= rotateLeft(x[7] &+ x[6], by: 13)
            x[5] ^= rotateLeft(x[4] &+ x[7], by: 18)

            x[11] ^= rotateLeft(x[10] &+ x[9], by: 7)
            x[8] ^= rotateLeft(x[11] &+ x[10], by: 9)
            x[9] ^= rotateLeft(x[8] &+ x[11], by: 13)
            x[10] ^= rotateLeft(x[9] &+ x[8], by: 18)

            x[12] ^= rotateLeft(x[15] &+ x[14], by: 7)
            x[13] ^= rotateLeft(x[12] &+ x[15], by: 9)
            x[14] ^= rotateLeft(x[13] &+ x[12], by: 13)
            x[15] ^= rotateLeft(x[14] &+ x[13], by: 18)
        }

        return x
    }

    private static func poly1305Authenticate(message: [UInt8], key: [UInt8]) -> [UInt8] {
        let r0 = Int64(load32(key, 0) & 0x3ffffff)
        let r1 = Int64((load32(key, 3) >> 2) & 0x3ffff03)
        let r2 = Int64((load32(key, 6) >> 4) & 0x3ffc0ff)
        let r3 = Int64((load32(key, 9) >> 6) & 0x3f03fff)
        let r4 = Int64((load32(key, 12) >> 8) & 0x00fffff)

        let s1 = r1 * 5
        let s2 = r2 * 5
        let s3 = r3 * 5
        let s4 = r4 * 5

        var h0: Int64 = 0
        var h1: Int64 = 0
        var h2: Int64 = 0
        var h3: Int64 = 0
        var h4: Int64 = 0

        var offset = 0
        while offset < message.count {
            let remaining = message.count - offset
            let blockCount = min(16, remaining)
            var block = [UInt8](repeating: 0, count: 17)
            for index in 0 ..< blockCount {
                block[index] = message[offset + index]
            }
            block[blockCount] = 1

            h0 += Int64(load32(block, 0) & 0x3ffffff)
            h1 += Int64((load32(block, 3) >> 2) & 0x3ffffff)
            h2 += Int64((load32(block, 6) >> 4) & 0x3ffffff)
            h3 += Int64((load32(block, 9) >> 6) & 0x3ffffff)
            h4 += Int64((load32(block, 12) >> 8) & 0x3ffffff)

            let d0 = (h0 * r0) + (h1 * s4) + (h2 * s3) + (h3 * s2) + (h4 * s1)
            let d1 = (h0 * r1) + (h1 * r0) + (h2 * s4) + (h3 * s3) + (h4 * s2)
            let d2 = (h0 * r2) + (h1 * r1) + (h2 * r0) + (h3 * s4) + (h4 * s3)
            let d3 = (h0 * r3) + (h1 * r2) + (h2 * r1) + (h3 * r0) + (h4 * s4)
            let d4 = (h0 * r4) + (h1 * r3) + (h2 * r2) + (h3 * r1) + (h4 * r0)

            var carry = d0 >> 26
            h0 = d0 & 0x3ffffff
            var acc1 = d1 + carry
            carry = acc1 >> 26
            h1 = acc1 & 0x3ffffff
            var acc2 = d2 + carry
            carry = acc2 >> 26
            h2 = acc2 & 0x3ffffff
            var acc3 = d3 + carry
            carry = acc3 >> 26
            h3 = acc3 & 0x3ffffff
            var acc4 = d4 + carry
            carry = acc4 >> 26
            h4 = acc4 & 0x3ffffff
            h0 += carry * 5
            carry = h0 >> 26
            h0 &= 0x3ffffff
            h1 += carry

            offset += blockCount
        }

        var carry = h1 >> 26
        h1 &= 0x3ffffff
        h2 += carry
        carry = h2 >> 26
        h2 &= 0x3ffffff
        h3 += carry
        carry = h3 >> 26
        h3 &= 0x3ffffff
        h4 += carry
        carry = h4 >> 26
        h4 &= 0x3ffffff
        h0 += carry * 5
        carry = h0 >> 26
        h0 &= 0x3ffffff
        h1 += carry

        var g0 = h0 + 5
        carry = g0 >> 26
        g0 &= 0x3ffffff
        var g1 = h1 + carry
        carry = g1 >> 26
        g1 &= 0x3ffffff
        var g2 = h2 + carry
        carry = g2 >> 26
        g2 &= 0x3ffffff
        var g3 = h3 + carry
        carry = g3 >> 26
        g3 &= 0x3ffffff
        let g4 = h4 + carry - (1 << 26)

        let mask = ~(g4 >> 63)
        let notMask = ~mask
        h0 = (h0 & notMask) | (g0 & mask)
        h1 = (h1 & notMask) | (g1 & mask)
        h2 = (h2 & notMask) | (g2 & mask)
        h3 = (h3 & notMask) | (g3 & mask)
        h4 = (h4 & notMask) | (g4 & mask)

        var f0 = UInt64(h0 | (h1 << 26)) + UInt64(load32(key, 16))
        var f1 = UInt64((h1 >> 6) | (h2 << 20)) + UInt64(load32(key, 20)) + (f0 >> 32)
        var f2 = UInt64((h2 >> 12) | (h3 << 14)) + UInt64(load32(key, 24)) + (f1 >> 32)
        var f3 = UInt64((h3 >> 18) | (h4 << 8)) + UInt64(load32(key, 28)) + (f2 >> 32)

        f0 &= 0xffff_ffff
        f1 &= 0xffff_ffff
        f2 &= 0xffff_ffff
        f3 &= 0xffff_ffff

        return store32(UInt32(f0)) + store32(UInt32(f1)) + store32(UInt32(f2)) + store32(UInt32(f3))
    }

    private static func load32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        let b0 = index < bytes.count ? UInt32(bytes[index]) : 0
        let b1 = index + 1 < bytes.count ? UInt32(bytes[index + 1]) << 8 : 0
        let b2 = index + 2 < bytes.count ? UInt32(bytes[index + 2]) << 16 : 0
        let b3 = index + 3 < bytes.count ? UInt32(bytes[index + 3]) << 24 : 0
        return b0 | b1 | b2 | b3
    }

    private static func store32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24),
        ]
    }

    private static func rotateLeft(_ value: UInt32, by shift: UInt32) -> UInt32 {
        (value << shift) | (value >> (32 - shift))
    }

    private static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        var diff: UInt8 = 0
        for index in 0 ..< lhs.count {
            diff |= lhs[index] ^ rhs[index]
        }
        return diff == 0
    }

    private static func fillRandomBytes(_ bytes: inout [UInt8]) throws {
#if canImport(Security)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CryptoBoxError.randomGenerationFailed
        }
#else
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min ... UInt8.max, using: &generator)
        }
#endif
    }

    private static let sigma: [UInt32] = [
        0x61707865,
        0x3320646e,
        0x79622d32,
        0x6b206574,
    ]
}
