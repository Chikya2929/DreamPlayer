package com.dreamplayer.app

import android.content.Context

/**
 * Kotlin facade over the libsmb2 JNI bridge (Smb2Native). Mirrors the iOS
 * LibSMB2Session/LibSMB2File helpers: one session owns one smb2_context plus
 * one tree connection to a share; files are opened read-only with positional
 * pread (no cursor), so a reader can be thrown away and rebuilt at any offset.
 *
 * Thread-safety: libsmb2 contexts are NOT thread-safe. Callers that need
 * concurrent reads (prefetch threads) must open one session per thread, or
 * serialise access. We open one session per SmbDataSource and serialise reads
 * through a lock, matching the iOS design.
 */
class LibSmb2Session private constructor(
    val host: String,
    val port: Int,
    val share: String,
    private val handle: Long,
) {
    val isOpen: Boolean get() = handle != 0L

    fun error(): String = if (handle != 0L) Smb2Native.getError(handle) else "no session"

    fun openFile(path: String): LibSmb2File? {
        if (handle == 0L) return null
        val fh = Smb2Native.openFile(handle, path)
        if (fh == 0L) return null
        return LibSmb2File(this, fh, path)
    }

    fun openDir(path: String): LibSmb2Dir? {
        if (handle == 0L) return null
        val dh = Smb2Native.openDir(handle, path)
        if (dh == 0L) return null
        return LibSmb2Dir(this, dh)
    }

    fun close() {
        if (handle != 0L) Smb2Native.closeSession(handle)
    }

    companion object {
        fun open(
            host: String, port: Int, user: String, pass: String,
            domain: String, share: String,
        ): LibSmb2Session? {
            val h = Smb2Native.openSession(host, port, user, pass, domain, share)
            if (h == 0L) return null
            return LibSmb2Session(host, port, share, h)
        }
    }
}

class LibSmb2File(
    private val session: LibSmb2Session,
    private val handle: Long,
    val path: String,
) {
    val size: Long get() = Smb2Native.fileSize(handle)

    fun readAt(offset: Long, buf: ByteArray, len: Int): Int {
        if (len <= 0) return 0
        val n = Smb2Native.readAt(handle, offset, buf, len)
        return if (n < 0) -1 else n
    }

    fun close() {
        Smb2Native.closeFile(handle)
    }
}

class LibSmb2Dir(
    private val session: LibSmb2Session,
    private val handle: Long,
) {
    fun entries(): List<LibSmb2Entry> {
        val rows = Smb2Native.readDir(handle) ?: return emptyList()
        val out = mutableListOf<LibSmb2Entry>()
        for (row in rows) {
            if (row.size < 4) continue
            out.add(LibSmb2Entry(
                name = row[0],
                isDirectory = row[1] == "1",
                size = row[2].toLongOrNull() ?: 0L,
                modifiedMillis = row[3].toLongOrNull() ?: 0L,
            ))
        }
        return out
    }

    fun close() {
        Smb2Native.closeDir(handle)
    }
}

data class LibSmb2Entry(
    val name: String,
    val isDirectory: Boolean,
    val size: Long,
    val modifiedMillis: Long,
)
