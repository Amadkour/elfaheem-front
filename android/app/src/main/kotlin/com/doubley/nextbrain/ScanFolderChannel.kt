package com.doubley.nextbrain

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * A document scanner's output folder for the paper-exam upload (Dart: lib/features/exams/paper/scan/
 * scan_folder_io.dart). Android gives an app no path access to another app's files (scoped storage: a scanner's PDFs
 * are invisible to java.io / dart:io without MANAGE_EXTERNAL_STORAGE), so the folder goes through the Storage Access
 * Framework: the system folder picker grants this activity read access to the tree it returns, and the tree is
 * walked and read through DocumentsContract — no storage permission at all.
 *
 *   pickTree      → {uri, name} | null (cancelled)
 *   list {uri}    → [{uri, name, path, size, mime}] every file under the tree, sub-folders included (path relative
 *                   to the picked folder); at most MAX_FILES, at most MAX_DEPTH levels
 *   read {uri}    → the file's bytes
 *
 * MainActivity registers it in configureFlutterEngine and hands it onActivityResult.
 */
class ScanFolderChannel private constructor(private val activity: Activity, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "ScanFolder"
        const val CHANNEL = "com.doubley.nextbrain/scan_folder"
        const val REQUEST_TREE = 4721
        private const val MAX_FILES = 5000
        private const val MAX_DEPTH = 8

        @Volatile private var instance: ScanFolderChannel? = null

        fun register(activity: Activity, messenger: BinaryMessenger): ScanFolderChannel =
            ScanFolderChannel(activity, messenger).also { instance = it }

        /** True when the result was the folder picker's (consumed). */
        fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
            instance?.handleResult(requestCode, resultCode, data) ?: false
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTree" -> pickTree(result)
                "list" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) result.error("bad_args", "uri missing", null) else list(Uri.parse(uri), result)
                }
                "read" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) result.error("bad_args", "uri missing", null) else read(Uri.parse(uri), result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pickTree(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A folder picker is already open", null)
            return
        }
        pending = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQUEST_TREE)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("unavailable", e.message, null)
        }
    }

    private fun handleResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_TREE) return false
        val r = pending ?: return true
        pending = null
        val tree = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (tree == null) {
            r.success(null)
            return true
        }
        io.execute {
            val name = try {
                val doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                displayName(doc)
            } catch (e: Exception) {
                null
            }
            main.post { r.success(mapOf("uri" to tree.toString(), "name" to (name ?: ""))) }
        }
        return true
    }

    private fun displayName(doc: Uri): String? =
        activity.contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    private fun list(tree: Uri, result: MethodChannel.Result) {
        io.execute {
            try {
                val out = ArrayList<Map<String, Any?>>()
                // breadth-first: (document id, path of the folder relative to the picked one, depth)
                val queue = ArrayDeque<Triple<String, String, Int>>()
                queue.add(Triple(DocumentsContract.getTreeDocumentId(tree), "", 0))
                val cols = arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                )
                while (queue.isNotEmpty() && out.size < MAX_FILES) {
                    val (id, prefix, depth) = queue.removeFirst()
                    val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
                    activity.contentResolver.query(children, cols, null, null, null)?.use { c ->
                        while (c.moveToNext() && out.size < MAX_FILES) {
                            // no `continue` here: this is the body of an inline lambda (use)
                            val childId: String? = c.getString(0)
                            val name: String? = c.getString(1)
                            val mime = c.getString(2) ?: ""
                            val path = if (prefix.isEmpty()) (name ?: "") else "$prefix/$name"
                            if (childId == null || name == null) {
                                // a row without an id or a name cannot be listed
                            } else if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                                if (depth + 1 <= MAX_DEPTH) queue.add(Triple(childId, path, depth + 1))
                            } else {
                                out.add(mapOf(
                                    "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, childId).toString(),
                                    "name" to name,
                                    "path" to path,
                                    "size" to (if (c.isNull(3)) null else c.getLong(3)),
                                    "mime" to mime,
                                ))
                            }
                        }
                    }
                }
                main.post { result.success(out) }
            } catch (e: Exception) {
                Log.w(TAG, "list failed", e)
                main.post { result.error("list_failed", e.message, null) }
            }
        }
    }

    private fun read(doc: Uri, result: MethodChannel.Result) {
        io.execute {
            try {
                val bytes = activity.contentResolver.openInputStream(doc)?.use { it.readBytes() }
                main.post { if (bytes == null) result.error("read_failed", "no stream", null) else result.success(bytes) }
            } catch (e: Exception) {
                Log.w(TAG, "read failed", e)
                main.post { result.error("read_failed", e.message, null) }
            }
        }
    }
}
