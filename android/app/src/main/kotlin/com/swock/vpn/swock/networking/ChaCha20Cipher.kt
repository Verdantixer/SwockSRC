package com.swock.vpn.swock.networking

import org.bouncycastle.crypto.modes.ChaCha20Poly1305
import org.bouncycastle.crypto.params.AEADParameters
import org.bouncycastle.crypto.params.KeyParameter

class ChaCha20Cipher {
    fun encrypt(plainText: ByteArray, keyHex: String, nonce: ByteArray, aad: ByteArray = ByteArray(0)): ByteArray {
        return process(true, plainText, keyHex, nonce, aad)
    }

    fun decrypt(cipherText: ByteArray, keyHex: String, nonce: ByteArray, aad: ByteArray = ByteArray(0)): ByteArray {
        return process(false, cipherText, keyHex, nonce, aad)
    }

    private fun process(
        encrypt: Boolean,
        input: ByteArray,
        keyHex: String,
        nonce: ByteArray,
        aad: ByteArray,
    ): ByteArray {
        require(nonce.size == 12) { "ChaCha20-Poly1305 requires a 12-byte nonce" }
        val cipher = ChaCha20Poly1305()
        cipher.init(encrypt, AEADParameters(KeyParameter(hexToBytes(keyHex)), 128, nonce, aad))
        val output = ByteArray(cipher.getOutputSize(input.size))
        val length = cipher.processBytes(input, 0, input.size, output, 0)
        val finalLength = cipher.doFinal(output, length)
        return output.copyOf(length + finalLength)
    }

    private fun hexToBytes(value: String): ByteArray {
        require(value.length == 64) { "ChaCha20 keys must be 32 bytes" }
        val out = ByteArray(value.length / 2)
        for (i in value.indices step 2) {
            out[i / 2] = value.substring(i, i + 2).toInt(16).toByte()
        }
        return out
    }
}
