package uback.rodvieirasilva.github.io

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    BackupSessionBus.setListener { payload ->
                        events?.success(payload)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    BackupSessionBus.setListener(null)
                }
            })
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDeviceName" -> {
                result.success(MediaDiscovery.getDeviceName(applicationContext))
            }

            "getAppVersion" -> {
                val info = runCatching {
                    packageManager.getPackageInfo(packageName, 0)
                }.getOrNull()
                val versionName = info?.versionName ?: "1.0.0"
                val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    info?.longVersionCode ?: 1L
                } else {
                    @Suppress("DEPRECATION")
                    (info?.versionCode ?: 1).toLong()
                }
                result.success("$versionName+$versionCode")
            }

            "checkPermissions" -> {
                result.success(currentPermissionState())
            }

            "requestMediaPermissions" -> {
                val needed = requiredRuntimePermissions().filter {
                    ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
                }
                if (needed.isEmpty()) {
                    result.success(currentPermissionState())
                } else {
                    pendingPermissionResult = result
                    ActivityCompat.requestPermissions(this, needed.toTypedArray(), PERM_REQUEST_CODE)
                }
            }

            "openAllFilesAccessSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    runCatching { startActivity(intent) }.onFailure {
                        startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                    }
                }
                result.success(true)
            }

            "discoverMedia" -> {
                val rawSources = call.argument<List<*>>("enabledSources")
                val enabledSources = rawSources
                    ?.mapNotNull { it as? String }
                    ?.toSet()
                    ?: setOf("camera", "screenshots")
                scope.launch {
                    try {
                        val items = withContext(Dispatchers.IO) {
                            MediaDiscovery.discover(
                                context = applicationContext,
                                enabledSources = enabledSources,
                            ).map { it.toMap() }
                        }
                        result.success(items)
                    } catch (e: Throwable) {
                        result.error("DISCOVER_ERROR", e.message, null)
                    }
                }
            }

            "getSourceStats" -> {
                scope.launch {
                    try {
                        val stats = withContext(Dispatchers.IO) {
                            MediaDiscovery.getSourceStats(applicationContext)
                        }
                        result.success(stats)
                    } catch (e: Throwable) {
                        result.error("STATS_ERROR", e.message, null)
                    }
                }
            }

            "testConnection" -> {
                val configMap = call.arguments as? Map<*, *>
                if (configMap == null) {
                    result.error("INVALID_ARGS", "Expected SMB config map", null)
                    return
                }
                val smbConfig = SmbConnectionConfig.fromMap(configMap)
                scope.launch {
                    try {
                        val msg = withContext(Dispatchers.IO) {
                            SmbTransferClient(smbConfig).use { it.testConnection() }
                        }
                        result.success(mapOf("ok" to true, "message" to msg))
                    } catch (e: Throwable) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "message" to (e.message ?: e.javaClass.simpleName),
                            ),
                        )
                    }
                }
            }

            "startBackup" -> {
                if (BackupSessionBus.isRunning.get()) {
                    result.error("ALREADY_RUNNING", "Backup is already running", null)
                    return
                }
                val smbMap = call.argument<Map<*, *>>("smbConfig")
                val mode = call.argument<String>("mode") ?: "copy"
                val deviceFolder = call.argument<String>("deviceFolder") ?: "android"
                val rawItems = call.argument<List<Map<*, *>>>("items") ?: emptyList()

                if (smbMap == null) {
                    result.error("INVALID_ARGS", "Missing smbConfig", null)
                    return
                }

                val items = rawItems.map { m ->
                    BackupItemPayload(
                        id = m["id"] as? String ?: "",
                        contentUri = m["contentUri"] as? String,
                        fileName = m["fileName"] as? String ?: "",
                        localPath = m["localPath"] as? String ?: "",
                        sourceFolder = m["sourceFolder"] as? String ?: "camera",
                        sizeBytes = (m["sizeBytes"] as? Number)?.toLong() ?: 0L,
                        createdAtMs = (m["createdAtMs"] as? Number)?.toLong() ?: 0L,
                    )
                }

                BackupSessionBus.pendingRequest = BackupJobRequest(
                    smbConfig = SmbConnectionConfig.fromMap(smbMap),
                    mode = mode,
                    deviceFolder = deviceFolder,
                    items = items,
                )

                val intent = Intent(this, BackupForegroundService::class.java).apply {
                    action = BackupForegroundService.ACTION_START
                }
                ContextCompat.startForegroundService(this, intent)
                result.success(true)
            }

            "stopBackup" -> {
                BackupSessionBus.cancelRequested.set(true)
                val intent = Intent(this, BackupForegroundService::class.java).apply {
                    action = BackupForegroundService.ACTION_STOP
                }
                runCatching { startService(intent) }
                result.success(true)
            }

            "getBackupStatus" -> {
                result.success(BackupSessionBus.latestEvent)
            }

            else -> result.notImplemented()
        }
    }

    private fun requiredRuntimePermissions(): List<String> {
        val perms = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            perms.add(Manifest.permission.READ_MEDIA_IMAGES)
            perms.add(Manifest.permission.READ_MEDIA_VIDEO)
            perms.add(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            perms.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        return perms
    }

    private fun currentPermissionState(): Map<String, Boolean> {
        val hasMedia = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) ==
                PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VIDEO) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

        val hasAllFiles = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }

        val hasNotifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        return mapOf(
            "hasMedia" to (hasMedia || hasAllFiles),
            "hasAllFiles" to hasAllFiles,
            "hasNotifications" to hasNotifications,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERM_REQUEST_CODE) {
            pendingPermissionResult?.success(currentPermissionState())
            pendingPermissionResult = null
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val METHOD_CHANNEL = "uback/native"
        private const val EVENT_CHANNEL = "uback/progress"
        private const val PERM_REQUEST_CODE = 1042
    }
}
