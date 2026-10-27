package com.dreamplayer.app

/**
 * JNI bridge to libsmb2 (see android/app/src/main/cpp/smb2_jni.c).
 * All handles are opaque longs; 0 means "failed / null".
 */
object Smb2Native {
    init {
        System.loadLibrary("smb2jni")
    }

    @JvmStatic external fun openSession(
        host: String, port: Int, user: String, pass: String,
        domain: String, share: String,
    ): Long

    @JvmStatic external fun closeSession(session: Long)

    @JvmStatic external fun getError(session: Long): String

    @JvmStatic external fun openFile(session: Long, path: String): Long

    @JvmStatic external fun closeFile(file: Long)

    @JvmStatic external fun fileSize(file: Long): Long

    /// The server's negotiated MaxReadSize (bytes). libsmb2 caps every read
    /// request at this value, so a larger readAt returns a short read.
    @JvmStatic external fun maxReadSize(file: Long): Int

    @JvmStatic external fun readAt(file: Long, offset: Long, buf: ByteArray, len: Int): Int

    @JvmStatic external fun openDir(session: Long, path: String): Long

    @JvmStatic external fun closeDir(dir: Long)

    // Each row: String[4] = {name, isDir("0"/"1"), size, mtimeMs}
    @JvmStatic external fun readDir(dir: Long): Array<Array<String>>?
}
