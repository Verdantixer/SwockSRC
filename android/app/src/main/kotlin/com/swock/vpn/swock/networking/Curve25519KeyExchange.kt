package com.swock.vpn.swock.networking

import org.bouncycastle.crypto.agreement.X25519Agreement
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters
import java.security.SecureRandom

class Curve25519KeyExchange {
    fun createSharedSecret(publicKeyHex: String, privateKeyHex: String): String {
        val privateKey = X25519PrivateKeyParameters(hexToBytes(privateKeyHex), 0)
        val publicKey = X25519PublicKeyParameters(hexToBytes(publicKeyHex), 0)
        val agreement = X25519Agreement()
        agreement.init(privateKey)
        val sharedSecret = ByteArray(agreement.agreementSize)
        agreement.calculateAgreement(publicKey, sharedSecret, 0)
        return bytesToHex(sharedSecret)
    }

    fun generateKeyPair(): Pair<String, String> {
        val privateKey = X25519PrivateKeyParameters(SecureRandom())
        return bytesToHex(privateKey.generatePublicKey().encoded) to bytesToHex(privateKey.encoded)
    }

    private fun hexToBytes(value: String): ByteArray {
        require(value.length == 64) { "Curve25519 keys must be 32 bytes" }
        val out = ByteArray(value.length / 2)
        for (i in value.indices step 2) {
            out[i / 2] = value.substring(i, i + 2).toInt(16).toByte()
        }
        return out
    }

    private fun bytesToHex(bytes: ByteArray): String {
        return bytes.joinToString(separator = "") { "%02x".format(it.toInt() and 0xff) }
    }
}
