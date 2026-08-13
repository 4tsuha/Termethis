package jp.yts.termethis

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.SystemClock
import android.text.Editable
import android.text.InputType
import android.text.Selection
import android.text.SpannableStringBuilder
import android.util.TypedValue
import android.view.Choreographer
import android.view.GestureDetector
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import com.termux.terminal.TerminalEmulator
import com.termux.terminal.TerminalOutput
import com.termux.terminal.TerminalSession
import com.termux.terminal.TerminalSessionClient
import com.termux.view.TerminalRenderer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.nio.charset.StandardCharsets
import java.util.ArrayDeque
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

internal const val TERMUX_TERMINAL_VIEW_TYPE = "jp.yts.termethis/termux_terminal"

internal class TermuxTerminalViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        TermuxTerminalPlatformView(
            context = context,
            messenger = messenger,
            viewId = viewId,
            creationArguments = args as? Map<*, *> ?: emptyMap<String, Any>(),
        )
}

private class TermuxTerminalPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    creationArguments: Map<*, *>,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "$TERMUX_TERMINAL_VIEW_TYPE/$viewId")
    private var options = TermuxTerminalOptions.from(creationArguments)
    private var active = true
    private var disposed = false
    private val pendingWrites = ArrayDeque<PendingTermuxWrite>()
    private var frameScheduled = false

    private val sessionClient: TerminalSessionClient = object : TerminalSessionClient {
        override fun onTextChanged(changedSession: TerminalSession) = invalidateTerminal()
        override fun onTitleChanged(changedSession: TerminalSession) = Unit
        override fun onSessionFinished(finishedSession: TerminalSession) = Unit
        override fun onCopyTextToClipboard(session: TerminalSession, text: String) = copyToClipboard(text)
        override fun onPasteTextFromClipboard(session: TerminalSession) = pasteClipboard()
        override fun onBell(session: TerminalSession) = Unit
        override fun onColorsChanged(session: TerminalSession) = invalidateTerminal()
        override fun onTerminalCursorStateChange(state: Boolean) = invalidateTerminal()
        override fun getTerminalCursorStyle(): Int? = TerminalEmulator.TERMINAL_CURSOR_STYLE_BLOCK
        override fun logError(tag: String, message: String) = Unit
        override fun logWarn(tag: String, message: String) = Unit
        override fun logInfo(tag: String, message: String) = Unit
        override fun logDebug(tag: String, message: String) = Unit
        override fun logVerbose(tag: String, message: String) = Unit
        override fun logStackTraceWithMessage(tag: String, message: String, error: Exception) = Unit
        override fun logStackTrace(tag: String, error: Exception) = Unit
    }

    private val terminalOutput: TerminalOutput = object : TerminalOutput() {
        override fun write(data: ByteArray, offset: Int, count: Int) {
            if (count <= 0) return
            emitInput(data.copyOfRange(offset, offset + count))
        }

        override fun titleChanged(oldTitle: String?, newTitle: String?) = Unit
        override fun onCopyTextToClipboard(text: String) = copyToClipboard(text)
        override fun onPasteTextFromClipboard() = pasteClipboard()
        override fun onBell() = Unit
        override fun onColorsChanged() = invalidateTerminal()
    }

    private val emulator: TerminalEmulator
    private var terminalViewOrNull: TermuxCanvasView? = null
    private val terminalView get() = checkNotNull(terminalViewOrNull)
    private val drainFrame = Choreographer.FrameCallback { drainWrites() }

    init {
        emulator = TerminalEmulator(
            terminalOutput,
            DEFAULT_COLUMNS,
            DEFAULT_ROWS,
            min(options.scrollbackLines, TerminalEmulator.TERMINAL_TRANSCRIPT_ROWS_MAX),
            sessionClient,
        )
        terminalViewOrNull = TermuxCanvasView(
            context,
            emulator,
            terminalOutput,
            onResize = { columns, rows ->
                if (!disposed) {
                    channel.invokeMethod(
                        "resize",
                        mapOf("columns" to columns, "rows" to rows),
                    )
                }
            },
        ).apply {
            applyOptions(options)
        }
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = terminalView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("disposed", "Termux terminal has been disposed", null)
            return
        }
        when (call.method) {
            "initialize" -> result.success(
                mapOf("renderer" to "termux", "scrollbackLines" to options.scrollbackLines),
            )
            "write" -> enqueueWrite(call, result)
            "setActive" -> {
                active = call.arguments == true
                terminalView.setTerminalActive(active)
                result.success(null)
            }
            "setOptions" -> {
                options = TermuxTerminalOptions.from(
                    call.arguments as? Map<*, *> ?: emptyMap<String, Any>(),
                )
                terminalView.applyOptions(options)
                result.success(null)
            }
            "focus" -> {
                active = true
                terminalView.setTerminalActive(true)
                result.success(null)
            }
            "paste" -> {
                val text = call.arguments as? String
                if (text == null) {
                    result.error("invalid_text", "Expected paste text", null)
                } else {
                    emulator.paste(text)
                    result.success(null)
                }
            }
            "sendKey" -> sendKey(call, result)
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        if (frameScheduled) Choreographer.getInstance().removeFrameCallback(drainFrame)
        while (pendingWrites.isNotEmpty()) {
            pendingWrites.removeFirst().result.error(
                "disposed",
                "Termux terminal has been disposed",
                null,
            )
        }
    }

    private fun enqueueWrite(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val data = arguments?.get("data") as? ByteArray
        if (data == null) {
            result.error("invalid_data", "Expected terminal bytes", null)
            return
        }
        pendingWrites.addLast(
            PendingTermuxWrite(data, reset = arguments["reset"] == true, result = result),
        )
        scheduleDrain()
    }

    private fun scheduleDrain() {
        if (frameScheduled || disposed) return
        frameScheduled = true
        Choreographer.getInstance().postFrameCallback(drainFrame)
    }

    private fun drainWrites() {
        frameScheduled = false
        if (disposed) return
        val startedAt = SystemClock.elapsedRealtimeNanos()
        while (pendingWrites.isNotEmpty()) {
            val pending = pendingWrites.first()
            if (pending.reset && pending.offset == 0) {
                emulator.reset()
                emulator.append(CLEAR_SEQUENCE, CLEAR_SEQUENCE.size)
            }
            val end = min(pending.data.size, pending.offset + PARSER_SLICE_BYTES)
            val slice = if (pending.offset == 0 && end == pending.data.size) {
                pending.data
            } else {
                pending.data.copyOfRange(pending.offset, end)
            }
            emulator.append(slice, slice.size)
            pending.offset = end
            if (pending.offset == pending.data.size) {
                pendingWrites.removeFirst()
                pending.result.success(null)
            }
            if (SystemClock.elapsedRealtimeNanos() - startedAt >= PARSER_BUDGET_NANOS) break
        }
        terminalView.onTerminalUpdated()
        if (pendingWrites.isNotEmpty()) scheduleDrain()
    }

    private fun sendKey(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val key = arguments?.get("key") as? String
        if (key == null) {
            result.error("invalid_key", "Expected terminal key", null)
            return
        }
        val packet = terminalKeyPacket(
            key = key,
            control = arguments["control"] == true,
            alt = arguments["alt"] == true,
            applicationCursorKeys = emulator.isCursorKeysApplicationMode,
        )
        if (packet.isEmpty()) {
            result.error("invalid_key", "Unsupported terminal key", null)
        } else {
            emitInput(packet, direct = true)
            result.success(null)
        }
    }

    private fun emitInput(bytes: ByteArray, direct: Boolean = false) {
        if (!disposed && bytes.isNotEmpty()) {
            channel.invokeMethod(if (direct) "directInput" else "input", bytes)
        }
    }

    private fun invalidateTerminal() {
        terminalViewOrNull?.postInvalidateOnAnimation()
    }

    private fun copyToClipboard(text: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Terminal", text))
    }

    private fun pasteClipboard() {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
        if (text.isNotEmpty()) emulator.paste(text)
    }

    private companion object {
        const val DEFAULT_COLUMNS = 80
        const val DEFAULT_ROWS = 24
        const val PARSER_SLICE_BYTES = 8 * 1024
        const val PARSER_BUDGET_NANOS = 2_000_000L
        val CLEAR_SEQUENCE = "\u001B[2J\u001B[H".toByteArray(StandardCharsets.US_ASCII)
    }
}

private class TermuxCanvasView(
    context: Context,
    private val emulator: TerminalEmulator,
    private val output: TerminalOutput,
    private val onResize: (columns: Int, rows: Int) -> Unit,
) : View(context) {
    private var options = TermuxTerminalOptions.from(emptyMap<String, Any>())
    private var renderer = createRenderer(options)
    private var cellWidth = measureCellWidth(options)
    private var lineHeight = measureLineHeight(options)
    private var topRow = 0
    private val gestureDetector = GestureDetector(context, TerminalGestureListener())

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        setBackgroundColor(Color.BLACK)
    }

    fun applyOptions(value: TermuxTerminalOptions) {
        options = value
        renderer = createRenderer(value)
        cellWidth = measureCellWidth(value)
        lineHeight = measureLineHeight(value)
        updateTerminalSize(width, height)
        postInvalidateOnAnimation()
    }

    fun setTerminalActive(active: Boolean) {
        if (active) {
            requestFocus()
            (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                .showSoftInput(this, InputMethodManager.SHOW_IMPLICIT)
        } else {
            clearFocus()
        }
    }

    fun onTerminalUpdated() {
        val history = emulator.screen.activeTranscriptRows
        topRow = topRow.coerceIn(-history, 0)
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.translate(horizontalPadding, verticalPadding)
        renderer.render(emulator, canvas, topRow, -1, -1, -1, -1)
        canvas.restore()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        updateTerminalSize(w, h)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean =
        gestureDetector.onTouchEvent(event) || super.onTouchEvent(event)

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN or EditorInfo.IME_ACTION_NONE
        val composingBuffer = SpannableStringBuilder().apply {
            Selection.setSelection(this, 0)
        }
        val commitTracker = TermuxImeCommitTracker()
        return object : BaseInputConnection(this, true) {
            override fun getEditable(): Editable = composingBuffer

            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
                commitTracker.commit(text)?.let(::sendCommittedBytes)
                clearComposingBuffer()
                return true
            }

            override fun finishComposingText(): Boolean {
                commitTracker.finish(composingBuffer)?.let(::sendCommittedBytes)
                clearComposingBuffer()
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                if (composingBuffer.isNotEmpty()) {
                    return super.deleteSurroundingText(beforeLength, afterLength)
                }
                repeat(beforeLength.coerceAtLeast(0)) { output.write(byteArrayOf(0x7f), 0, 1) }
                return true
            }

            private fun sendCommittedBytes(bytes: ByteArray) {
                output.write(bytes, 0, bytes.size)
            }

            private fun clearComposingBuffer() {
                composingBuffer.clearSpans()
                composingBuffer.clear()
                Selection.setSelection(composingBuffer, 0)
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val packet = hardwareKeyPacket(keyCode, event, emulator.isCursorKeysApplicationMode)
        if (packet.isEmpty()) return super.onKeyDown(keyCode, event)
        output.write(packet, 0, packet.size)
        return true
    }

    private fun updateTerminalSize(viewWidth: Int, viewHeight: Int) {
        if (viewWidth <= 0 || viewHeight <= 0) return
        val columns = max(4, ((viewWidth - horizontalPadding * 2) / cellWidth).toInt())
        val rows = max(4, ((viewHeight - verticalPadding * 2) / lineHeight).toInt())
        if (columns != emulator.mColumns || rows != emulator.mRows) {
            emulator.resize(columns, rows)
            topRow = 0
            onResize(columns, rows)
        }
    }

    private fun createRenderer(value: TermuxTerminalOptions): TerminalRenderer = TerminalRenderer(
        spToPx(value.fontSize).roundToInt(),
        terminalTypeface(context, value.terminalFontFamily, value.japaneseFontFamily),
    )

    private fun measureCellWidth(value: TermuxTerminalOptions): Float = Paint().run {
        typeface = terminalTypeface(context, value.terminalFontFamily, value.japaneseFontFamily)
        textSize = spToPx(value.fontSize)
        measureText("X").coerceAtLeast(1f)
    }

    private fun measureLineHeight(value: TermuxTerminalOptions): Float = Paint().run {
        typeface = terminalTypeface(context, value.terminalFontFamily, value.japaneseFontFamily)
        textSize = spToPx(value.fontSize)
        ceil(fontSpacing.toDouble()).toFloat().coerceAtLeast(1f)
    }

    private fun spToPx(value: Float): Float = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_SP,
        value,
        resources.displayMetrics,
    )

    private fun terminalCoordinates(event: MotionEvent): Pair<Int, Int> {
        val column = ((event.x - horizontalPadding) / cellWidth).toInt().coerceAtLeast(0) + 1
        val row = ((event.y - verticalPadding) / lineHeight).toInt().coerceAtLeast(0) + 1
        return column to row
    }

    private inner class TerminalGestureListener : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(event: MotionEvent): Boolean = true

        override fun onSingleTapUp(event: MotionEvent): Boolean {
            requestFocus()
            if (options.mouseInput && emulator.isMouseTrackingActive) {
                val (column, row) = terminalCoordinates(event)
                emulator.sendMouseEvent(TerminalEmulator.MOUSE_LEFT_BUTTON, column, row, true)
                emulator.sendMouseEvent(TerminalEmulator.MOUSE_LEFT_BUTTON, column, row, false)
            } else {
                (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                    .showSoftInput(this@TermuxCanvasView, InputMethodManager.SHOW_IMPLICIT)
            }
            return true
        }

        override fun onLongPress(event: MotionEvent) {
            if (!options.mouseInput || !options.longPressRightClick || !emulator.isMouseTrackingActive) {
                return
            }
            val (column, row) = terminalCoordinates(event)
            emulator.sendMouseEvent(MOUSE_RIGHT_BUTTON, column, row, true)
            emulator.sendMouseEvent(MOUSE_RIGHT_BUTTON, column, row, false)
        }

        override fun onScroll(
            first: MotionEvent?,
            current: MotionEvent,
            distanceX: Float,
            distanceY: Float,
        ): Boolean {
            if (options.mouseInput && emulator.isMouseTrackingActive) {
                val (column, row) = terminalCoordinates(current)
                emulator.sendMouseEvent(
                    if (distanceY < 0) {
                        TerminalEmulator.MOUSE_WHEELUP_BUTTON
                    } else {
                        TerminalEmulator.MOUSE_WHEELDOWN_BUTTON
                    },
                    column,
                    row,
                    true,
                )
            } else {
                val history = emulator.screen.activeTranscriptRows
                val rows = (distanceY / lineHeight).roundToInt()
                topRow = (topRow + rows).coerceIn(-history, 0)
                postInvalidateOnAnimation()
            }
            return true
        }
    }

    private val horizontalPadding get() = 4f * resources.displayMetrics.density
    private val verticalPadding get() = 6f * resources.displayMetrics.density

    private companion object {
        const val MOUSE_RIGHT_BUTTON = 2
    }
}

internal class TermuxImeCommitTracker {
    fun commit(text: CharSequence?): ByteArray? {
        return encode(text?.toString().orEmpty())
    }

    fun finish(composing: CharSequence): ByteArray? = encode(composing.toString())

    private fun encode(text: String): ByteArray? =
        text.takeIf(String::isNotEmpty)?.toByteArray(StandardCharsets.UTF_8)
}

private data class TermuxTerminalOptions(
    val scrollbackLines: Int,
    val fontSize: Float,
    val terminalFontFamily: String,
    val japaneseFontFamily: String,
    val mouseInput: Boolean,
    val longPressRightClick: Boolean,
) {
    companion object {
        fun from(values: Map<*, *>): TermuxTerminalOptions = TermuxTerminalOptions(
            scrollbackLines = ((values["scrollbackLines"] as? Number)?.toInt() ?: 2000)
                .coerceIn(200, TerminalEmulator.TERMINAL_TRANSCRIPT_ROWS_MAX),
            fontSize = ((values["fontSize"] as? Number)?.toFloat() ?: 14f)
                .coerceIn(6f, 30f),
            terminalFontFamily = values["terminalFontFamily"] as? String ?: "CascadiaMono",
            japaneseFontFamily = values["japaneseFontFamily"] as? String ?: "NotoSansJP",
            mouseInput = values["mouseInput"] == true,
            longPressRightClick = values["longPressRightClick"] == true,
        )
    }
}

private data class PendingTermuxWrite(
    val data: ByteArray,
    val reset: Boolean,
    val result: MethodChannel.Result,
    var offset: Int = 0,
)

private fun terminalKeyPacket(
    key: String,
    control: Boolean,
    alt: Boolean,
    applicationCursorKeys: Boolean,
): ByteArray {
    val modifiers = (if (alt) 2 else 0) or (if (control) 4 else 0)
    val modifierParameter = modifiers + 1
    val arrowFinal = when (key) {
        "arrowUp" -> 'A'
        "arrowDown" -> 'B'
        "arrowRight" -> 'C'
        "arrowLeft" -> 'D'
        else -> null
    }
    if (arrowFinal != null) {
        val sequence = when {
            modifiers != 0 -> "\u001B[1;${modifierParameter}$arrowFinal"
            applicationCursorKeys -> "\u001BO$arrowFinal"
            else -> "\u001B[$arrowFinal"
        }
        return sequence.toByteArray(StandardCharsets.US_ASCII)
    }
    val literal = when (key) {
        "escape" -> '\u001B'
        "tab" -> '\t'
        "enter" -> '\r'
        else -> return ByteArray(0)
    }
    val sequence = when {
        control -> "\u001B[${literal.code};${modifierParameter}u"
        alt -> "\u001B$literal"
        else -> literal.toString()
    }
    return sequence.toByteArray(StandardCharsets.US_ASCII)
}

private fun hardwareKeyPacket(
    keyCode: Int,
    event: KeyEvent,
    applicationCursorKeys: Boolean,
): ByteArray {
    val namedKey = when (keyCode) {
        KeyEvent.KEYCODE_DPAD_UP -> "arrowUp"
        KeyEvent.KEYCODE_DPAD_DOWN -> "arrowDown"
        KeyEvent.KEYCODE_DPAD_LEFT -> "arrowLeft"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "arrowRight"
        KeyEvent.KEYCODE_ESCAPE -> "escape"
        KeyEvent.KEYCODE_TAB -> "tab"
        KeyEvent.KEYCODE_ENTER -> "enter"
        else -> null
    }
    if (namedKey != null) {
        return terminalKeyPacket(
            namedKey,
            control = event.isCtrlPressed,
            alt = event.isAltPressed,
            applicationCursorKeys = applicationCursorKeys,
        )
    }
    if (keyCode == KeyEvent.KEYCODE_DEL) return byteArrayOf(0x7f)
    var codePoint = event.unicodeChar
    if (codePoint == 0) return ByteArray(0)
    if (event.isCtrlPressed && codePoint in 'a'.code..'z'.code) codePoint -= 96
    if (event.isCtrlPressed && codePoint in 'A'.code..'Z'.code) codePoint -= 64
    val text = String(Character.toChars(codePoint)).toByteArray(StandardCharsets.UTF_8)
    return if (event.isAltPressed) byteArrayOf(0x1b) + text else text
}
