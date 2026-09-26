import CryptoKit
import Foundation

/// The nonce that ties one Apple identity token to one sign-in attempt on one device.
///
/// Apple is given the SHA-256 of the raw value and echoes that digest back inside the
/// token. The raw value goes to PLUG's server instead, which hashes it and compares. A
/// token captured from somebody else's sign-in carries somebody else's digest and fails
/// that comparison, which is what stops a valid token for this app from being reusable.
struct SignInNonce {
    let raw: String

    init() {
        // URL-safe characters only: the value travels in a JSON body the server validates
        // against a character-set pattern before it looks at anything else.
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        raw = String((0..<32).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    /// Lower-case hexadecimal, which is the form Apple expects in the request's nonce.
    var hashedForApple: String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
