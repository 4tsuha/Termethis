package jp.yts.termethis

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class SftpFileTransferChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "jp.yts.termethis/sftp_file_transfer"
        private const val PICK_FILES = 4110
        private const val PICK_DIRECTORY = 4111
        private const val EXPORT_FILE = 4112
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSource: File? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (pendingResult != null) {
                result.error("transfer_busy", "Another file operation is active", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "pickFiles" -> launchFilePicker(result)
                "pickDirectory" -> launchDirectoryPicker(result)
                "exportFile" -> launchFileExporter(
                    result,
                    call.argument<String>("localPath"),
                    call.argument<String>("fileName"),
                    call.argument<String>("mimeType"),
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun launchFilePicker(result: MethodChannel.Result) {
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        activity.startActivityForResult(intent, PICK_FILES)
    }

    private fun launchDirectoryPicker(result: MethodChannel.Result) {
        pendingResult = result
        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), PICK_DIRECTORY)
    }

    private fun launchFileExporter(
        result: MethodChannel.Result,
        localPath: String?,
        fileName: String?,
        mimeType: String?,
    ) {
        val source = localPath?.let(::File)
        val cacheRoot = activity.cacheDir.canonicalFile
        if (source == null || !source.isFile || !source.canonicalFile.toPath().startsWith(cacheRoot.toPath())) {
            result.error("invalid_source", "Export source must be an app cache file", null)
            return
        }
        pendingResult = result
        pendingSource = source
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType?.takeIf { it.contains('/') } ?: "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, sanitizeName(fileName ?: source.name))
        }
        activity.startActivityForResult(intent, EXPORT_FILE)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode !in setOf(PICK_FILES, PICK_DIRECTORY, EXPORT_FILE)) return false
        if (resultCode != Activity.RESULT_OK) {
            complete(null)
            return true
        }
        when (requestCode) {
            PICK_FILES -> importFiles(data)
            PICK_DIRECTORY -> importDirectory(data?.data)
            EXPORT_FILE -> exportFile(data?.data)
        }
        return true
    }

    private fun importFiles(data: Intent?) {
        val uris = buildList {
            data?.clipData?.let { clip ->
                repeat(clip.itemCount) { add(clip.getItemAt(it).uri) }
            }
            data?.data?.let(::add)
        }.distinct()
        if (uris.isEmpty()) {
            fail("selection_empty", "No files were selected")
            return
        }
        executor.execute {
            val transferRoot = createTransferRoot()
            runCatching {
                uris.map { uri ->
                    val name = sanitizeName(displayName(uri) ?: "file")
                    val destination = uniqueChild(transferRoot, name)
                    copyDocument(uri, destination)
                    mapOf("name" to destination.name, "path" to destination.absolutePath)
                }
            }.onSuccess(::complete).onFailure {
                transferRoot.deleteRecursively()
                fail("import_failed", "Unable to import selected files")
            }
        }
    }

    private fun importDirectory(treeUri: Uri?) {
        if (treeUri == null) {
            fail("selection_empty", "No directory was selected")
            return
        }
        executor.execute {
            val transferRoot = createTransferRoot()
            runCatching {
                val rootName = sanitizeName(displayName(treeUri) ?: "folder")
                val destinationRoot = uniqueChild(transferRoot, rootName).apply { mkdirs() }
                copyTree(treeUri, destinationRoot)
                mapOf("name" to destinationRoot.name, "path" to destinationRoot.absolutePath)
            }.onSuccess(::complete).onFailure {
                transferRoot.deleteRecursively()
                fail("import_failed", "Unable to import selected directory")
            }
        }
    }

    private fun exportFile(destination: Uri?) {
        val source = pendingSource
        if (destination == null || source == null) {
            fail("selection_empty", "No export destination was selected")
            return
        }
        executor.execute {
            runCatching {
                source.inputStream().buffered().use { input ->
                    activity.contentResolver.openOutputStream(destination, "w")?.buffered()?.use { output ->
                        input.copyTo(output, 64 * 1024)
                    } ?: error("Unable to open export destination")
                }
                true
            }.onSuccess(::complete).onFailure {
                fail("export_failed", "Unable to save downloaded file")
            }
        }
    }

    private fun copyTree(treeUri: Uri, destinationRoot: File) {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val queue = ArrayDeque<Pair<String, File>>()
        queue.add(rootId to destinationRoot)
        while (queue.isNotEmpty()) {
            val (parentId, localParent) = queue.removeFirst()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
            activity.contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val typeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
                while (cursor.moveToNext()) {
                    val childId = cursor.getString(idColumn)
                    val name = sanitizeName(cursor.getString(nameColumn))
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
                    val destination = uniqueChild(localParent, name)
                    if (cursor.getString(typeColumn) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        destination.mkdirs()
                        queue.add(childId to destination)
                    } else {
                        copyDocument(childUri, destination)
                    }
                }
            }
        }
    }

    private fun copyDocument(uri: Uri, destination: File) {
        activity.contentResolver.openInputStream(uri)?.buffered()?.use { input ->
            destination.outputStream().buffered().use { output -> input.copyTo(output, 64 * 1024) }
        } ?: error("Unable to read selected document")
    }

    private fun displayName(uri: Uri): String? = activity.contentResolver.query(
        uri,
        arrayOf(OpenableColumns.DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
    }

    private fun createTransferRoot(): File =
        File(activity.cacheDir, "sftp_transfer/${UUID.randomUUID()}").apply { mkdirs() }

    private fun uniqueChild(parent: File, requestedName: String): File {
        var candidate = File(parent, requestedName)
        var index = 2
        while (candidate.exists()) {
            candidate = File(parent, "$requestedName ($index)")
            index += 1
        }
        return candidate
    }

    private fun sanitizeName(value: String): String {
        val clean = value.replace(Regex("[\\\\/\\u0000]"), "_").trim().take(255)
        return clean.takeUnless { it.isEmpty() || it == "." || it == ".." } ?: "item"
    }

    private fun complete(value: Any?) = activity.runOnUiThread {
        pendingResult?.success(value)
        clearPending()
    }

    private fun fail(code: String, message: String) = activity.runOnUiThread {
        pendingResult?.error(code, message, null)
        clearPending()
    }

    private fun clearPending() {
        pendingResult = null
        pendingSource = null
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingResult?.error("activity_destroyed", "Activity closed during file operation", null)
        clearPending()
        executor.shutdownNow()
    }
}
