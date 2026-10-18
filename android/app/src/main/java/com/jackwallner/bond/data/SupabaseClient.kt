package com.jackwallner.bond.data

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

data class HttpResponse(val status: Int, val body: String, val headers: Map<String, String> = emptyMap())

/** One HTTP exchange. Unit tests swap in a recording fake. */
fun interface HttpTransport {
    @Throws(IOException::class)
    fun execute(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse
}

class UrlConnectionTransport : HttpTransport {
    override fun execute(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 20_000
            headers.forEach { (key, value) -> setRequestProperty(key, value) }
            if (body != null) doOutput = true
        }
        try {
            if (body != null) connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            val responseHeaders = connection.headerFields
                .filterKeys { it != null }
                .mapKeys { it.key.lowercase() }
                .mapValues { it.value.joinToString(",") }
            return HttpResponse(status, text, responseHeaders)
        } finally {
            connection.disconnect()
        }
    }
}

/** A PostgREST or GoTrue error. `message` carries the server's text, e.g. "invalid or expired code". */
class SupabaseException(val status: Int, message: String) : IOException(message)

data class AuthSession(
    val accessToken: String,
    val refreshToken: String,
    val expiresAt: Long,
    val userId: UUID,
    val isAnonymous: Boolean,
)

/**
 * The slice of supabase-swift Bond uses, over plain REST: anonymous GoTrue
 * sessions with refresh, PostgREST reads and writes, and RPCs. Same project,
 * same anon key, same row level security as the iOS app.
 */
class SupabaseClient(
    private val baseUrl: String,
    private val anonKey: String,
    private val store: KeyValueStore,
    private val transport: HttpTransport = UrlConnectionTransport(),
    private val nowSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    private val authLock = Mutex()

    var session: AuthSession? = loadSession()
        private set

    // Auth

    /** A cached session, refreshed when close to expiry. Null when there is none or it was revoked. */
    suspend fun restoreSession(): AuthSession? = authLock.withLock {
        val current = session ?: return@withLock null
        if (current.expiresAt - 60 > nowSeconds()) return@withLock current
        refreshLocked(current)
    }

    suspend fun signInAnonymously(): AuthSession = authLock.withLock {
        val response = send("POST", "$baseUrl/auth/v1/signup", JSONObject().toString(), token = null)
        parseSession(JSONObject(response.body)).also(::saveSession)
    }

    /** Drops the local session. The server-side refresh token is revoked best-effort. */
    suspend fun signOut() {
        val current = session
        clearSession()
        if (current != null) {
            runCatching { send("POST", "$baseUrl/auth/v1/logout?scope=local", null, token = current.accessToken) }
        }
    }

    fun clearSession() {
        session = null
        store.remove(SESSION_KEY)
    }

    private suspend fun refreshLocked(current: AuthSession): AuthSession? {
        return try {
            val body = JSONObject().put("refresh_token", current.refreshToken).toString()
            val response = send("POST", "$baseUrl/auth/v1/token?grant_type=refresh_token", body, token = null)
            parseSession(JSONObject(response.body)).also(::saveSession)
        } catch (error: SupabaseException) {
            // 400/401: the refresh token is gone (account deleted, revoked). Anything
            // else (5xx) keeps the stored session so an outage does not mint a new user.
            if (error.status in 400..499) {
                clearSession()
                null
            } else {
                throw error
            }
        }
    }

    private suspend fun accessToken(): String {
        val current = session ?: throw SupabaseException(401, "Not signed in")
        if (current.expiresAt - 60 > nowSeconds()) return current.accessToken
        return authLock.withLock {
            val latest = session ?: throw SupabaseException(401, "Not signed in")
            if (latest.expiresAt - 60 > nowSeconds()) latest.accessToken
            else refreshLocked(latest)?.accessToken ?: throw SupabaseException(401, "Session expired")
        }
    }

    // PostgREST

    suspend fun select(table: String, query: String): JSONArray {
        val response = authed("GET", "$baseUrl/rest/v1/$table?$query", null)
        return JSONArray(response.body.ifBlank { "[]" })
    }

    /** Row count from `Content-Range` with `Prefer: count=exact`. */
    suspend fun count(table: String): Int? {
        val response = authed("HEAD", "$baseUrl/rest/v1/$table?select=id", null, extra = mapOf("Prefer" to "count=exact"))
        return response.headers["content-range"]?.substringAfter('/')?.toIntOrNull()
    }

    suspend fun insert(table: String, rows: Any) {
        authed("POST", "$baseUrl/rest/v1/$table", rows.toString(), extra = mapOf("Prefer" to "return=minimal"))
    }

    suspend fun upsert(table: String, row: JSONObject, onConflict: String? = null): JSONArray {
        val url = "$baseUrl/rest/v1/$table" + (onConflict?.let { "?on_conflict=${encode(it)}" } ?: "")
        val response = authed(
            "POST", url, row.toString(),
            extra = mapOf("Prefer" to "resolution=merge-duplicates,return=representation"),
        )
        return JSONArray(response.body.ifBlank { "[]" })
    }

    suspend fun delete(table: String, filter: String) {
        authed("DELETE", "$baseUrl/rest/v1/$table?$filter", null, extra = mapOf("Prefer" to "return=minimal"))
    }

    suspend fun rpc(function: String, params: JSONObject): String =
        authed("POST", "$baseUrl/rest/v1/rpc/$function", params.toString()).body

    private suspend fun authed(
        method: String,
        url: String,
        body: String?,
        extra: Map<String, String> = emptyMap(),
    ): HttpResponse = send(method, url, body, accessToken(), extra)

    private suspend fun send(
        method: String,
        url: String,
        body: String?,
        token: String?,
        extra: Map<String, String> = emptyMap(),
    ): HttpResponse = withContext(Dispatchers.IO) {
        val headers = buildMap {
            put("apikey", anonKey)
            put("Authorization", "Bearer ${token ?: anonKey}")
            put("Accept", "application/json")
            if (body != null) put("Content-Type", "application/json")
            putAll(extra)
        }
        val response = transport.execute(method, url, headers, body)
        if (response.status !in 200..299) throw SupabaseException(response.status, errorMessage(response))
        response
    }

    private fun errorMessage(response: HttpResponse): String {
        val parsed = runCatching { JSONObject(response.body) }.getOrNull()
        val text = parsed?.let {
            it.optString("message").ifBlank { it.optString("msg") }.ifBlank { it.optString("error_description") }
        }
        return text?.takeIf { it.isNotBlank() } ?: "HTTP ${response.status}"
    }

    private fun parseSession(o: JSONObject): AuthSession {
        val user = o.getJSONObject("user")
        val expiresAt = if (o.has("expires_at")) o.getLong("expires_at") else nowSeconds() + o.optLong("expires_in", 3600)
        return AuthSession(
            accessToken = o.getString("access_token"),
            refreshToken = o.getString("refresh_token"),
            expiresAt = expiresAt,
            userId = UUID.fromString(user.getString("id")),
            isAnonymous = user.optBoolean("is_anonymous", false),
        )
    }

    private fun saveSession(value: AuthSession) {
        session = value
        val json = JSONObject()
            .put("access_token", value.accessToken)
            .put("refresh_token", value.refreshToken)
            .put("expires_at", value.expiresAt)
            .put("user_id", value.userId.toString())
            .put("is_anonymous", value.isAnonymous)
        store.putString(SESSION_KEY, json.toString())
    }

    private fun loadSession(): AuthSession? = runCatching {
        val o = JSONObject(store.getString(SESSION_KEY) ?: return null)
        AuthSession(
            accessToken = o.getString("access_token"),
            refreshToken = o.getString("refresh_token"),
            expiresAt = o.getLong("expires_at"),
            userId = UUID.fromString(o.getString("user_id")),
            isAnonymous = o.optBoolean("is_anonymous", true),
        )
    }.getOrNull()

    companion object {
        private const val SESSION_KEY = "supabase.session"

        fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())
    }
}
