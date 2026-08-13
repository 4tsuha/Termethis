package jp.yts.termethis

import java.nio.charset.StandardCharsets
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TermuxImeCommitBufferTest {
    @Test
    fun `commit sends hiragana kanji and emoji as utf8 exactly once`() {
        val buffer = TermuxImeCommitTracker()

        assertArrayEquals(
            "日本語😀".toByteArray(StandardCharsets.UTF_8),
            buffer.commit("日本語😀"),
        )
        assertNull(buffer.finish(""))
    }

    @Test
    fun `finish sends composing text when ime finishes without commit`() {
        val buffer = TermuxImeCommitTracker()

        assertArrayEquals(
            "かな".toByteArray(StandardCharsets.UTF_8),
            buffer.finish("かな"),
        )
        assertNull(buffer.finish(""))
    }

    @Test
    fun `empty commit does not emit terminal input`() {
        val buffer = TermuxImeCommitTracker()

        assertNull(buffer.commit(""))
        assertNull(buffer.finish(""))
    }
}
