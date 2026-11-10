// Prints the EdDSA public key (base64) for a Sparkle private key read from standard input, so the
// release workflow can check that the SPARKLE_ED_PRIVATE_KEY secret matches the app's SUPublicEDKey
// before publishing. Never prints the private key.
// Usage: printf '%s' "$KEY" | xcrun swift tools/sparkle-public-key.swift
import CryptoKit
import Foundation

let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
// Sparkle exports the 32-byte seed in base64 (older keys: 64 or 96 bytes, starting with the seed).
guard let data = Data(base64Encoded: input), [32, 64, 96].contains(data.count),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data.prefix(32)) else {
    FileHandle.standardError.write(Data("not a Sparkle EdDSA private key\n".utf8))
    exit(1)
}
print(key.publicKey.rawRepresentation.base64EncodedString())
