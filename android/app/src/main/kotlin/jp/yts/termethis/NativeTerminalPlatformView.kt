package jp.yts.termethis

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Typeface
import android.graphics.fonts.Font
import android.graphics.fonts.FontFamily
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.view.View
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.unit.sp
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.connectbot.terminal.MouseDragPhase
import org.connectbot.terminal.Terminal
import org.connectbot.terminal.TerminalEmulator
import org.connectbot.terminal.TerminalEmulatorFactory
import org.connectbot.terminal.TerminalGestureCallback

internal const val NATIVE_TERMINAL_VIEW_TYPE = "jp.yts.termethis/native_terminal"

internal class NativeTerminalViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        NativeTerminalPlatformView(
            context = context,
            messenger = messenger,
            viewId = viewId,
            creationArguments = args as? Map<*, *> ?: emptyMap<String, Any>(),
        )
}

private class NativeTerminalPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    creationArguments: Map<*, *>,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "$NATIVE_TERMINAL_VIEW_TYPE/$viewId")
    private var options by mutableStateOf(NativeTerminalOptions.from(creationArguments))
    private var active by mutableStateOf(true)
    private val modeTracker = TerminalModeTracker()
    private var disposed = false
    private val parserThread = HandlerThread(
        "TermethisTerminalParser-$viewId",
        Process.THREAD_PRIORITY_DISPLAY,
    ).apply { start() }
    private val parserHandler = Handler(parserThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())

    private val emulator: TerminalEmulator = TerminalEmulatorFactory.create(
        initialRows = 24,
        initialCols = 80,
        defaultForeground = Color(0xFFF2F2F2),
        defaultBackground = Color.Black,
        maxScrollbackLines = options.scrollbackLines,
        autoDetectUrls = true,
        onKeyboardInput = ::emitInput,
        onResize = { dimensions ->
            mainHandler.post {
                if (!disposed) {
                    channel.invokeMethod(
                        "resize",
                        mapOf("columns" to dimensions.columns, "rows" to dimensions.rows),
                    )
                }
            }
        },
        onClipboardCopy = { text -> copyToClipboard(text) },
        looper = parserThread.looper,
    )

    private val mouseGestures = object : TerminalGestureCallback {
        override fun onTap(col: Int, row: Int): Boolean {
            if (!options.mouseInput || !modeTracker.mouseActive) return false
            emitInput(modeTracker.mousePacket(button = 0, col = col, row = row, pressed = true))
            emitInput(modeTracker.mousePacket(button = 0, col = col, row = row, pressed = false))
            return true
        }

        override fun onLongPress(col: Int, row: Int): Boolean {
            if (!options.mouseInput || !modeTracker.mouseActive || !options.longPressRightClick) {
                return false
            }
            emitInput(modeTracker.mousePacket(button = 2, col = col, row = row, pressed = true))
            emitInput(modeTracker.mousePacket(button = 2, col = col, row = row, pressed = false))
            return true
        }

        override fun onScroll(col: Int, row: Int, scrollUp: Boolean): Boolean {
            if (!options.mouseInput || !modeTracker.mouseActive) return false
            emitInput(
                modeTracker.mousePacket(
                    button = if (scrollUp) 64 else 65,
                    col = col,
                    row = row,
                    pressed = true,
                ),
            )
            return true
        }

        override fun onMouseDrag(col: Int, row: Int, phase: MouseDragPhase): Boolean {
            if (!options.mouseInput || !modeTracker.mouseActive) return false
            when (phase) {
                MouseDragPhase.Start -> emitInput(
                    modeTracker.mousePacket(button = 0, col = col, row = row, pressed = true),
                )
                MouseDragPhase.Move -> emitInput(
                    modeTracker.mousePacket(button = 32, col = col, row = row, pressed = true),
                )
                MouseDragPhase.End -> emitInput(
                    modeTracker.mousePacket(button = 0, col = col, row = row, pressed = false),
                )
            }
            return true
        }
    }

    private val composeView = ComposeView(context).apply {
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
        setBackgroundColor(android.graphics.Color.BLACK)
        setContent {
            val currentOptions = options
            val currentTypeface = remember(
                currentOptions.terminalFontFamily,
                currentOptions.japaneseFontFamily,
            ) {
                terminalTypeface(
                    context,
                    currentOptions.terminalFontFamily,
                    currentOptions.japaneseFontFamily,
                )
            }
            MaterialTheme {
                Terminal(
                    terminalEmulator = emulator,
                    modifier = Modifier.fillMaxSize(),
                    typeface = currentTypeface,
                    initialFontSize = currentOptions.fontSize.sp,
                    minFontSize = 6.sp,
                    maxFontSize = 30.sp,
                    backgroundColor = Color.Black,
                    foregroundColor = Color(0xFFF2F2F2),
                    keyboardEnabled = active,
                    showSoftKeyboard = active,
                    allowStandardKeyboard = true,
                    gestureCallback = if (currentOptions.mouseInput && modeTracker.mouseActive) {
                        mouseGestures
                    } else {
                        null
                    },
                    mouseModeActive = currentOptions.mouseInput && modeTracker.mouseActive,
                    tapToPositionCursorOnPrompt = currentOptions.tapToMovePromptCursor,
                    reflowOnKeyboard = currentOptions.resizeForKeyboard,
                    onPasteShortcut = ::pasteClipboard,
                    onPasteRequest = ::pasteClipboard,
                    onHyperlinkClick = { uri -> channel.invokeMethod("openLink", uri) },
                )
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = composeView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("disposed", "Native terminal has been disposed", null)
            return
        }
        when (call.method) {
            "initialize" -> result.success(
                mapOf("renderer" to "termlib", "scrollbackLines" to options.scrollbackLines),
            )
            "write" -> {
                val arguments = call.arguments as? Map<*, *>
                val data = arguments?.get("data") as? ByteArray
                if (data == null) {
                    result.error("invalid_data", "Expected terminal bytes", null)
                    return
                }
                val reset = arguments["reset"] == true
                parserHandler.post {
                    if (disposed) {
                        mainHandler.post {
                            result.error("disposed", "Native terminal has been disposed", null)
                        }
                        return@post
                    }
                    if (reset) {
                        modeTracker.reset()
                        emulator.writeInput(RESET_SEQUENCE)
                    }
                    modeTracker.scan(data)
                    emulator.writeInput(data)
                    mainHandler.post {
                        if (disposed) {
                            result.error("disposed", "Native terminal has been disposed", null)
                        } else {
                            result.success(null)
                        }
                    }
                }
            }
            "setActive" -> {
                active = call.arguments == true
                result.success(null)
            }
            "setOptions" -> {
                options = NativeTerminalOptions.from(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                result.success(null)
            }
            "focus" -> {
                active = true
                composeView.requestFocus()
                result.success(null)
            }
            "paste" -> {
                val text = call.arguments as? String
                if (text == null) {
                    result.error("invalid_text", "Expected paste text", null)
                } else {
                    emitInput(modeTracker.pastePacket(text))
                    result.success(null)
                }
            }
            "sendKey" -> {
                val arguments = call.arguments as? Map<*, *>
                val key = arguments?.get("key") as? String
                if (key == null || key !in SUPPORTED_KEYS) {
                    result.error("invalid_key", "Unsupported terminal key", null)
                    return
                }
                val control = arguments["control"] == true
                val alt = arguments["alt"] == true
                parserHandler.post {
                    val packet = modeTracker.keyPacket(key, control = control, alt = alt)
                    mainHandler.post {
                        if (!disposed) emitInput(packet, direct = true)
                        result.success(null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        composeView.disposeComposition()
        parserHandler.post {
            emulator.close()
            parserThread.quitSafely()
        }
    }

    private fun emitInput(bytes: ByteArray, direct: Boolean = false) {
        if (!disposed && bytes.isNotEmpty()) {
            mainHandler.post {
                if (!disposed) {
                    channel.invokeMethod(if (direct) "directInput" else "input", bytes)
                }
            }
        }
    }

    private fun copyToClipboard(text: String) {
        mainHandler.post {
            if (!disposed) {
                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("Terminal", text))
            }
        }
    }

    private fun pasteClipboard() {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
        if (text.isNotEmpty()) emitInput(modeTracker.pastePacket(text))
    }

    private companion object {
        val RESET_SEQUENCE = byteArrayOf(0x1B, 'c'.code.toByte())
        val SUPPORTED_KEYS = setOf(
            "escape",
            "tab",
            "enter",
            "arrowUp",
            "arrowDown",
            "arrowLeft",
            "arrowRight",
        )
    }
}

private data class NativeTerminalOptions(
    val scrollbackLines: Int,
    val fontSize: Float,
    val terminalFontFamily: String,
    val japaneseFontFamily: String,
    val mouseInput: Boolean,
    val longPressRightClick: Boolean,
    val tapToMovePromptCursor: Boolean,
    val resizeForKeyboard: Boolean,
) {
    companion object {
        fun from(values: Map<*, *>): NativeTerminalOptions = NativeTerminalOptions(
            scrollbackLines = ((values["scrollbackLines"] as? Number)?.toInt() ?: 2000)
                .coerceIn(200, 100_000),
            fontSize = ((values["fontSize"] as? Number)?.toFloat() ?: 14f)
                .coerceIn(6f, 30f),
            terminalFontFamily = values["terminalFontFamily"] as? String ?: "CascadiaMono",
            japaneseFontFamily = values["japaneseFontFamily"] as? String ?: "NotoSansJP",
            mouseInput = values["mouseInput"] == true,
            longPressRightClick = values["longPressRightClick"] == true,
            tapToMovePromptCursor = values["tapToMovePromptCursor"] == true,
            resizeForKeyboard = values["resizeForKeyboard"] == true,
        )
    }
}

private class TerminalModeTracker {
    private val parameterBuffer = StringBuilder(32)
    private var parserState = 0
    @Volatile private var applicationCursorKeys = false
    @Volatile private var bracketedPasteEnabled = false
    @Volatile private var sgrMouseEnabled = false
    @Volatile private var mouse1000 = false
    @Volatile private var mouse1002 = false
    @Volatile private var mouse1003 = false
    var mouseActive by mutableStateOf(false)
        private set

    val sgrMouse: Boolean get() = sgrMouseEnabled
    val bracketedPaste: Boolean get() = bracketedPasteEnabled

    fun reset() {
        parserState = 0
        parameterBuffer.clear()
        applicationCursorKeys = false
        bracketedPasteEnabled = false
        sgrMouseEnabled = false
        mouse1000 = false
        mouse1002 = false
        mouse1003 = false
        mouseActive = false
    }

    fun scan(data: ByteArray) {
        for (byte in data) {
            val value = byte.toInt() and 0xFF
            when (parserState) {
                0 -> if (value == 0x1B) parserState = 1
                1 -> parserState = when (value) {
                    '['.code -> 2
                    0x1B -> 1
                    else -> 0
                }
                2 -> parserState = when (value) {
                    '?'.code -> {
                        parameterBuffer.clear()
                        3
                    }
                    0x1B -> 1
                    else -> 0
                }
                3 -> when {
                    value in '0'.code..'9'.code || value == ';'.code -> {
                        if (parameterBuffer.length < 64) {
                            parameterBuffer.append(value.toChar())
                        } else {
                            parserState = 0
                            parameterBuffer.clear()
                        }
                    }
                    value == 'h'.code || value == 'l'.code -> {
                        updateModes(enabled = value == 'h'.code)
                        parserState = 0
                        parameterBuffer.clear()
                    }
                    value == 0x1B -> {
                        parserState = 1
                        parameterBuffer.clear()
                    }
                    else -> {
                        parserState = 0
                        parameterBuffer.clear()
                    }
                }
            }
        }
    }

    private fun updateModes(enabled: Boolean) {
        parameterBuffer
            .splitToSequence(';')
            .mapNotNull(String::toIntOrNull)
            .forEach { mode ->
                when (mode) {
                    1 -> applicationCursorKeys = enabled
                    1000 -> mouse1000 = enabled
                    1002 -> mouse1002 = enabled
                    1003 -> mouse1003 = enabled
                    1006 -> sgrMouseEnabled = enabled
                    2004 -> bracketedPasteEnabled = enabled
                }
            }
        mouseActive = mouse1000 || mouse1002 || mouse1003
    }

    fun keyPacket(key: String, control: Boolean, alt: Boolean): ByteArray {
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
            return sequence.toByteArray(Charsets.US_ASCII)
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
        return sequence.toByteArray(Charsets.US_ASCII)
    }

    fun pastePacket(text: String): ByteArray {
        val normalized = text.replace("\r\n", "\n").replace('\r', '\n')
        val payload = if (bracketedPaste) {
            "\u001B[200~$normalized\u001B[201~"
        } else {
            normalized
        }
        return payload.toByteArray(Charsets.UTF_8)
    }

    fun mousePacket(button: Int, col: Int, row: Int, pressed: Boolean): ByteArray {
        val x = col.coerceAtLeast(0) + 1
        val y = row.coerceAtLeast(0) + 1
        if (sgrMouse) {
            val suffix = if (pressed || button >= 64 || button and 32 != 0) 'M' else 'm'
            return "\u001B[<$button;$x;${y}$suffix".toByteArray(Charsets.US_ASCII)
        }
        val legacyButton = if (pressed) button else 3
        return byteArrayOf(
            0x1B,
            '['.code.toByte(),
            'M'.code.toByte(),
            (32 + legacyButton).coerceAtMost(255).toByte(),
            (32 + x.coerceAtMost(223)).toByte(),
            (32 + y.coerceAtMost(223)).toByte(),
        )
    }

}

internal fun terminalTypeface(
    context: Context,
    terminalFontFamily: String,
    japaneseFontFamily: String,
): Typeface {
    val primaryPath = when (terminalFontFamily) {
        "JetBrainsMono" -> "flutter_assets/assets/fonts/JetBrainsMono-VF.ttf"
        else -> "flutter_assets/assets/fonts/CascadiaMono.ttf"
    }
    if (Build.VERSION.SDK_INT < 29) {
        return runCatching { Typeface.createFromAsset(context.assets, primaryPath) }
            .getOrDefault(Typeface.MONOSPACE)
    }
    val languageFallbackPaths = when (japaneseFontFamily) {
        "Koruri" -> listOf("flutter_assets/assets/fonts/Koruri-Regular.ttf")
        "Mejiro" -> listOf("flutter_assets/assets/fonts/Mejiro-Regular.ttf")
        "Roboto" -> listOf(
            "flutter_assets/assets/fonts/Roboto-VF.ttf",
            "flutter_assets/assets/fonts/NotoSansJP-VF.ttf",
        )
        "Moralerspace" -> listOf("flutter_assets/assets/fonts/Moralerspace-Regular.ttf")
        "SourceCodePro" -> listOf(
            "flutter_assets/assets/fonts/SourceCodePro-VF.ttf",
            "flutter_assets/assets/fonts/NotoSansJP-VF.ttf",
        )
        "JetBrainsMono" -> listOf(
            "flutter_assets/assets/fonts/JetBrainsMono-VF.ttf",
            "flutter_assets/assets/fonts/NotoSansJP-VF.ttf",
        )
        else -> listOf("flutter_assets/assets/fonts/NotoSansJP-VF.ttf")
    }
    val fallbackPaths = languageFallbackPaths +
        "flutter_assets/assets/fonts/SymbolsNerdFontMono-Regular.ttf"
    return runCatching {
        val primary = FontFamily.Builder(Font.Builder(context.assets, primaryPath).build()).build()
        val builder = Typeface.CustomFallbackBuilder(primary)
        for (fallbackPath in fallbackPaths) {
            val fallback = FontFamily.Builder(
                Font.Builder(context.assets, fallbackPath).build(),
            ).build()
            builder.addCustomFallback(fallback)
        }
        builder.setSystemFallback("sans-serif")
        builder.build()
    }.getOrElse {
        runCatching { Typeface.createFromAsset(context.assets, primaryPath) }
            .getOrDefault(Typeface.MONOSPACE)
    }
}
