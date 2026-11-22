package uback.rodvieirasilva.github.io

import android.content.Context
import android.os.Build
import android.util.Log
import org.drinkless.tdlib.Client
import org.drinkless.tdlib.TdApi
import java.io.File
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/**
 * Manages the TDLib [Client] lifecycle, authorization state machine, and synchronous query helpers.
 */
object TelegramClientManager {
    private const val TAG = "UBack"
    private const val QUERY_TIMEOUT_SECONDS = 15L

    @Volatile
    private var client: Client? = null

    @Volatile
    private var authState: String = "uninitialized"

    @Volatile
    private var lastError: String? = null

    @Volatile
    private var currentApiId: Int = 0

    @Volatile
    private var currentApiHash: String = ""

    private val lock = Any()

    fun getAuthState(): Map<String, Any?> = mapOf(
        "state" to authState,
        "error" to lastError,
    )

    fun ensureInitializedFromPrefs(context: Context): Map<String, Any?> {
        if (authState == "ready") return getAuthState()
        val prefs = context.getSharedPreferences("uback_telegram_prefs", Context.MODE_PRIVATE)
        val savedId = prefs.getInt("api_id", 0)
        val savedHash = prefs.getString("api_hash", "") ?: ""
        if (savedId <= 0 || savedHash.isBlank()) return getAuthState()
        return ensureInitialized(context, savedId, savedHash)
    }

    fun ensureInitialized(context: Context, apiId: Int, apiHash: String): Map<String, Any?> {
        if (apiId <= 0 || apiHash.isBlank()) {
            authState = "unconfigured"
            lastError = "Telegram API ID and API Hash are required."
            return getAuthState()
        }
        context.getSharedPreferences("uback_telegram_prefs", Context.MODE_PRIVATE)
            .edit()
            .putInt("api_id", apiId)
            .putString("api_hash", apiHash.trim())
            .apply()
        synchronized(lock) {
            if (client != null && currentApiId == apiId && currentApiHash == apiHash && authState != "closed") {
                return getAuthState()
            }
            currentApiId = apiId
            currentApiHash = apiHash.trim()
            lastError = null
            try {
                Client.execute(TdApi.SetLogVerbosityLevel(1))
            } catch (e: Throwable) {
                Log.w(TAG, "TDLib SetLogVerbosityLevel failed: ${e.message}")
            }
            val appCtx = context.applicationContext
            client = Client.create(
                { obj -> handleUpdate(appCtx, obj) },
                { e -> Log.w(TAG, "TDLib update exception: ${e.message}") },
                { e -> Log.w(TAG, "TDLib default exception: ${e.message}") },
            )
            // Give TDLib a brief moment to emit initial AuthorizationState
            Thread.sleep(300)
        }
        return getAuthState()
    }

    private fun handleUpdate(context: Context, obj: TdApi.Object) {
        if (obj is TdApi.UpdateAuthorizationState) {
            when (obj.authorizationState) {
                is TdApi.AuthorizationStateWaitTdlibParameters -> {
                    authState = "initializing"
                    val params = TdApi.SetTdlibParameters().apply {
                        useTestDc = false
                        databaseDirectory = File(context.filesDir, "tdlib_db").absolutePath
                        filesDirectory = File(context.cacheDir, "tdlib_files").absolutePath
                        databaseEncryptionKey = ByteArray(0)
                        useFileDatabase = false
                        useChatInfoDatabase = true
                        useMessageDatabase = true
                        useSecretChats = false
                        apiId = currentApiId
                        apiHash = currentApiHash
                        systemLanguageCode = "en"
                        deviceModel = Build.MODEL ?: "Android"
                        systemVersion = Build.VERSION.RELEASE ?: "14"
                        applicationVersion = "1.2"
                    }
                    client?.send(params) { res ->
                        if (res is TdApi.Error) {
                            lastError = res.message
                            Log.e(TAG, "TDLib SetTdlibParameters error: ${res.message}")
                        }
                    }
                }
                is TdApi.AuthorizationStateWaitPhoneNumber -> {
                    authState = "waitPhoneNumber"
                    lastError = null
                }
                is TdApi.AuthorizationStateWaitCode -> {
                    authState = "waitCode"
                    lastError = null
                }
                is TdApi.AuthorizationStateWaitPassword -> {
                    authState = "waitPassword"
                    lastError = null
                }
                is TdApi.AuthorizationStateReady -> {
                    authState = "ready"
                    lastError = null
                }
                is TdApi.AuthorizationStateClosing -> {
                    authState = "closing"
                }
                is TdApi.AuthorizationStateClosed -> {
                    authState = "closed"
                    client = null
                }
            }
        }
    }

    fun sendPhoneNumber(phone: String): Map<String, Any?> {
        val c = client ?: return mapOf("state" to authState, "error" to "Client not initialized")
        val res = sendBlocking(c, TdApi.SetAuthenticationPhoneNumber(phone.trim(), null))
        if (res is TdApi.Error) {
            lastError = res.message
        } else {
            lastError = null
            Thread.sleep(400)
        }
        return getAuthState()
    }

    fun sendCode(code: String): Map<String, Any?> {
        val c = client ?: return mapOf("state" to authState, "error" to "Client not initialized")
        val res = sendBlocking(c, TdApi.CheckAuthenticationCode(code.trim()))
        if (res is TdApi.Error) {
            lastError = res.message
        } else {
            lastError = null
            Thread.sleep(400)
        }
        return getAuthState()
    }

    fun sendPassword(password: String): Map<String, Any?> {
        val c = client ?: return mapOf("state" to authState, "error" to "Client not initialized")
        val res = sendBlocking(c, TdApi.CheckAuthenticationPassword(password))
        if (res is TdApi.Error) {
            lastError = res.message
        } else {
            lastError = null
            Thread.sleep(400)
        }
        return getAuthState()
    }

    fun logout(context: Context): Map<String, Any?> {
        val c = client
        if (c != null) {
            sendBlocking(c, TdApi.LogOut())
            Thread.sleep(400)
        }
        File(context.filesDir, "tdlib_db").deleteRecursively()
        File(context.cacheDir, "tdlib_files").deleteRecursively()
        authState = "uninitialized"
        lastError = null
        client = null
        return getAuthState()
    }

    fun <T : TdApi.Object> query(
        function: TdApi.Function<T>,
        timeoutSeconds: Long = QUERY_TIMEOUT_SECONDS,
    ): TdApi.Object? {
        val c = client ?: return null
        return sendBlocking(c, function, timeoutSeconds)
    }

    private fun <T : TdApi.Object> sendBlocking(
        c: Client,
        function: TdApi.Function<T>,
        timeoutSeconds: Long = QUERY_TIMEOUT_SECONDS,
    ): TdApi.Object? {
        val future = CompletableFuture<TdApi.Object>()
        c.send(function) { obj -> future.complete(obj) }
        return try {
            future.get(timeoutSeconds, TimeUnit.SECONDS)
        } catch (e: Throwable) {
            Log.w(TAG, "TDLib query timeout/error (${function.javaClass.simpleName}): ${e.message}")
            null
        }
    }
}
