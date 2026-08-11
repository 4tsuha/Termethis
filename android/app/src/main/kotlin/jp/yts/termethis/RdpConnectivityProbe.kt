package jp.yts.termethis

import java.io.IOException
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket

internal enum class RdpProbeResult {
    AVAILABLE,
    UNREACHABLE,
    PROTOCOL_MISMATCH,
}

internal object RdpConnectivityProbe {
    private const val CONNECT_TIMEOUT_MILLIS = 2500
    private const val READ_TIMEOUT_MILLIS = 2500
    private const val MAXIMUM_RESPONSE_BYTES = 8192

    private val negotiationRequest = byteArrayOf(
        0x03,
        0x00,
        0x00,
        0x13,
        0x0e,
        0xe0.toByte(),
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x08,
        0x00,
        0x0b,
        0x00,
        0x00,
        0x00,
    )

    fun check(host: String, port: Int): RdpProbeResult = try {
        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MILLIS)
            socket.soTimeout = READ_TIMEOUT_MILLIS
            socket.getOutputStream().apply {
                write(negotiationRequest)
                flush()
            }

            val header = socket.getInputStream().readExactly(4)
                ?: return RdpProbeResult.PROTOCOL_MISMATCH
            val responseLength =
                ((header[2].toInt() and 0xff) shl 8) or
                    (header[3].toInt() and 0xff)
            if (
                header[0] != 0x03.toByte() ||
                responseLength !in 11..MAXIMUM_RESPONSE_BYTES
            ) {
                return RdpProbeResult.PROTOCOL_MISMATCH
            }

            val payload = socket.getInputStream().readExactly(responseLength - header.size)
                ?: return RdpProbeResult.PROTOCOL_MISMATCH
            if (payload.size < 7 || payload[1] != 0xd0.toByte()) {
                RdpProbeResult.PROTOCOL_MISMATCH
            } else {
                RdpProbeResult.AVAILABLE
            }
        }
    } catch (_: IOException) {
        RdpProbeResult.UNREACHABLE
    } catch (_: SecurityException) {
        RdpProbeResult.UNREACHABLE
    }

    private fun InputStream.readExactly(length: Int): ByteArray? {
        val bytes = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val count = read(bytes, offset, length - offset)
            if (count < 0) return null
            offset += count
        }
        return bytes
    }
}
