package jp.yts.termethis

import java.io.ByteArrayOutputStream
import java.util.ArrayDeque
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.system.exitProcess

/** Runs as Shizuku's shell/root identity, outside the Android app process. */
class DiagnosticsUserService : IDiagnosticsUserService.Stub() {
    companion object {
        private const val MIN_LOGCAT_LINES = 100
        private const val MAX_LOGCAT_LINES = 10_000
        private const val MAX_LOGCAT_LINE_CHARS = 4_096
        private const val MAX_LOGCAT_REPLY_LINES = 200
        private const val MAX_LOGCAT_REPLY_CHARS = 256 * 1024
        private const val MAX_SHELL_INPUT_BYTES = 8 * 1024
        private const val MAX_SHELL_OUTPUT_BYTES = 1024 * 1024
        private const val MAX_SHELL_REPLY_BYTES = 64 * 1024
    }

    private val logcatLock = Any()
    private val logcatLines = ArrayDeque<String>()
    private var logcatLineLimit = 2_000

    @Volatile
    private var logcatProcess: Process? = null

    @Volatile
    private var logcatReader: Thread? = null

    private val shellLock = Any()
    private val shellOutput = ArrayDeque<ByteArray>()
    private var shellOutputBytes = 0
    @Volatile
    private var shellInput: ArrayBlockingQueue<ByteArray>? = null

    @Volatile
    private var shellProcess: Process? = null

    @Volatile
    private var shellReader: Thread? = null

    @Volatile
    private var shellWriter: Thread? = null

    override fun startLogcatCapture(maxLines: Int): Boolean {
        synchronized(logcatLock) {
            if (logcatProcess?.isAlive == true) return true
            logcatLineLimit = maxLines.coerceIn(MIN_LOGCAT_LINES, MAX_LOGCAT_LINES)
            val process = ProcessBuilder(
                "/system/bin/logcat",
                "-v",
                "threadtime",
                "-T",
                "1",
            ).redirectErrorStream(true).start()
            logcatProcess = process
            logcatReader = thread(name = "termethis-logcat-reader", isDaemon = true) {
                try {
                    process.inputStream.bufferedReader().useLines { lines ->
                        lines.forEach { appendLogcatLine(process, it) }
                    }
                } finally {
                    synchronized(logcatLock) {
                        if (logcatProcess === process) {
                            logcatProcess = null
                            logcatReader = null
                        }
                    }
                }
            }
            return true
        }
    }

    override fun stopLogcatCapture() {
        synchronized(logcatLock) {
            logcatProcess?.destroy()
            logcatProcess = null
            logcatReader?.interrupt()
            logcatReader = null
        }
    }

    override fun isLogcatCapturing(): Boolean = logcatProcess?.isAlive == true

    override fun getRecentLogcatLines(limit: Int): MutableList<String> {
        val safeLimit = limit.coerceIn(1, MAX_LOGCAT_REPLY_LINES)
        synchronized(logcatLock) {
            val reply = ArrayDeque<String>()
            var characters = 0
            val iterator = logcatLines.descendingIterator()
            while (iterator.hasNext() && reply.size < safeLimit) {
                val line = iterator.next()
                if (characters + line.length > MAX_LOGCAT_REPLY_CHARS) break
                reply.addFirst(line)
                characters += line.length
            }
            return reply.toMutableList()
        }
    }

    override fun clearLogcatCapture() {
        synchronized(logcatLock) { logcatLines.clear() }
    }

    override fun startShell(): Boolean {
        synchronized(shellLock) {
            if (shellProcess?.isAlive == true) return true
            val inputQueue = ArrayBlockingQueue<ByteArray>(64)
            shellInput = inputQueue
            shellOutput.clear()
            shellOutputBytes = 0
            val process = ProcessBuilder("/system/bin/sh", "-i")
                .redirectErrorStream(true)
                .apply { environment()["TERM"] = "xterm-256color" }
                .start()
            shellProcess = process
            shellReader = thread(name = "termethis-shizuku-shell-reader", isDaemon = true) {
                val buffer = ByteArray(8 * 1024)
                try {
                    process.inputStream.use { input ->
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            appendShellOutput(process, buffer.copyOf(count))
                        }
                    }
                } finally {
                    synchronized(shellLock) {
                        if (shellProcess === process) {
                            shellProcess = null
                            shellReader = null
                            shellWriter?.interrupt()
                            shellWriter = null
                            shellInput = null
                        }
                    }
                }
            }
            shellWriter = thread(name = "termethis-shizuku-shell-writer", isDaemon = true) {
                try {
                    process.outputStream.use { output ->
                        while (process.isAlive) {
                            val input = inputQueue.poll(250, TimeUnit.MILLISECONDS) ?: continue
                            output.write(input)
                            output.flush()
                        }
                    }
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
            return true
        }
    }

    override fun writeShellInput(input: ByteArray): Boolean {
        if (input.isEmpty() || input.size > MAX_SHELL_INPUT_BYTES) return false
        if (shellProcess?.isAlive != true) return false
        val inputQueue = shellInput ?: return false
        return inputQueue.offer(input.copyOf())
    }

    override fun readShellOutput(maxBytes: Int): ByteArray {
        val safeMaximum = maxBytes.coerceIn(1, MAX_SHELL_REPLY_BYTES)
        synchronized(shellLock) {
            if (shellOutput.isEmpty()) return ByteArray(0)
            val output = ByteArrayOutputStream(safeMaximum)
            while (shellOutput.isNotEmpty() && output.size() < safeMaximum) {
                val chunk = shellOutput.removeFirst()
                shellOutputBytes -= chunk.size
                val remaining = safeMaximum - output.size()
                if (chunk.size <= remaining) {
                    output.write(chunk)
                } else {
                    output.write(chunk, 0, remaining)
                    val unused = chunk.copyOfRange(remaining, chunk.size)
                    shellOutput.addFirst(unused)
                    shellOutputBytes += unused.size
                }
            }
            return output.toByteArray()
        }
    }

    override fun isShellRunning(): Boolean = shellProcess?.isAlive == true

    override fun stopShell() {
        synchronized(shellLock) {
            shellProcess?.destroy()
            shellProcess = null
            shellReader?.interrupt()
            shellReader = null
            shellWriter?.interrupt()
            shellWriter = null
            shellInput?.clear()
            shellInput = null
        }
    }

    override fun destroy() {
        stopLogcatCapture()
        stopShell()
        exitProcess(0)
    }

    private fun appendLogcatLine(process: Process, value: String) {
        val line = if (value.length <= MAX_LOGCAT_LINE_CHARS) {
            value
        } else {
            value.take(MAX_LOGCAT_LINE_CHARS)
        }
        synchronized(logcatLock) {
            if (logcatProcess !== process) return
            logcatLines.addLast(line)
            while (logcatLines.size > logcatLineLimit) logcatLines.removeFirst()
        }
    }

    private fun appendShellOutput(process: Process, chunk: ByteArray) {
        synchronized(shellLock) {
            if (shellProcess !== process) return
            shellOutput.addLast(chunk)
            shellOutputBytes += chunk.size
            while (shellOutputBytes > MAX_SHELL_OUTPUT_BYTES && shellOutput.isNotEmpty()) {
                shellOutputBytes -= shellOutput.removeFirst().size
            }
        }
    }
}
