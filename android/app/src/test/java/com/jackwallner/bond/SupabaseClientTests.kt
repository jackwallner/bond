package com.jackwallner.bond

import com.jackwallner.bond.data.HttpResponse
import com.jackwallner.bond.data.HttpTransport
import com.jackwallner.bond.data.InMemoryStore
import com.jackwallner.bond.data.SupabaseClient
import com.jackwallner.bond.data.SupabaseException
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The PostgREST and GoTrue contract the iOS SDK speaks, checked against a fake transport. */
class SupabaseClientTests {
    private data class Call(val method: String, val url: String, val headers: Map<String, String>, val body: String?)

    private val calls = mutableListOf<Call>()
    private val responses = ArrayDeque<HttpResponse>()
    private val transport = HttpTransport { method, url, headers, body ->
        calls += Call(method, url, headers, body)
        responses.removeFirst()
    }
    private val store = InMemoryStore()
    private var nowSeconds = 1_000_000L
    private val userId = UUID.randomUUID()

    private fun client() = SupabaseClient("https://x.supabase.co", "anon", store, transport) { nowSeconds }

    private fun session(token: String, expiresAt: Long) = HttpResponse(
        200,
        JSONObject().put("access_token", token).put("refresh_token", "r-$token").put("expires_at", expiresAt)
            .put("user", JSONObject().put("id", userId.toString()).put("is_anonymous", true)).toString(),
    )

    @Test fun anonymousSignInIsPersisted() = runTest {
        responses += session("a1", nowSeconds + 3600)
        val s = client().signInAnonymously()
        assertEquals(userId, s.userId)
        assertTrue(s.isAnonymous)
        assertEquals("https://x.supabase.co/auth/v1/signup", calls.single().url)
        assertEquals("a1", client().session?.accessToken)
    }

    @Test fun nearExpiryRefreshesOnRestore() = runTest {
        responses += session("a1", nowSeconds + 30)
        client().signInAnonymously()
        responses += session("a2", nowSeconds + 3600)
        assertEquals("a2", client().restoreSession()?.accessToken)
        assertTrue(calls.last().url.endsWith("/auth/v1/token?grant_type=refresh_token"))
        assertEquals("r-a1", JSONObject(calls.last().body!!).getString("refresh_token"))
    }

    @Test fun revokedRefreshClearsTheSession() = runTest {
        responses += session("a1", nowSeconds + 30)
        val c = client()
        c.signInAnonymously()
        responses += HttpResponse(400, """{"error_description":"Invalid Refresh Token"}""")
        assertNull(c.restoreSession())
        assertNull(c.session)
    }

    @Test fun outageKeepsTheSession() = runTest {
        responses += session("a1", nowSeconds + 30)
        val c = client()
        c.signInAnonymously()
        responses += HttpResponse(503, "")
        try {
            c.restoreSession()
            fail("expected a 503")
        } catch (e: SupabaseException) {
            assertEquals(503, e.status)
        }
        assertNotNull(c.session)
    }

    @Test fun restCallsCarryTheUserTokenAndApiKey() = runTest {
        responses += session("a1", nowSeconds + 3600)
        val c = client()
        c.signInAnonymously()
        responses += HttpResponse(200, """[{"id":1}]""")
        assertEquals(1, c.select("couples", "select=*&limit=1").length())
        val call = calls.last()
        assertEquals("Bearer a1", call.headers["Authorization"])
        assertEquals("anon", call.headers["apikey"])
        assertEquals("https://x.supabase.co/rest/v1/couples?select=*&limit=1", call.url)
    }

    @Test fun countReadsContentRange() = runTest {
        responses += session("a1", nowSeconds + 3600)
        val c = client()
        c.signInAnonymously()
        responses += HttpResponse(200, "", mapOf("content-range" to "0-29/30"))
        assertEquals(30, c.count("daily_questions"))
        assertEquals("HEAD", calls.last().method)
        assertEquals("count=exact", calls.last().headers["Prefer"])
    }

    @Test fun upsertMergesOnTheConflictColumns() = runTest {
        responses += session("a1", nowSeconds + 3600)
        val c = client()
        c.signInAnonymously()
        responses += HttpResponse(201, "[]")
        c.upsert("question_responses", JSONObject().put("response", "hi"), onConflict = "question_id,couple_id,user_id")
        val call = calls.last()
        assertEquals("https://x.supabase.co/rest/v1/question_responses?on_conflict=question_id%2Ccouple_id%2Cuser_id", call.url)
        assertEquals("resolution=merge-duplicates,return=representation", call.headers["Prefer"])
    }

    @Test fun rpcErrorsSurfaceTheMessage() = runTest {
        responses += session("a1", nowSeconds + 3600)
        val c = client()
        c.signInAnonymously()
        responses += HttpResponse(400, """{"code":"P0001","message":"invalid or expired code"}""")
        try {
            c.rpc("consume_invite_code", JSONObject())
            fail("expected an error")
        } catch (e: SupabaseException) {
            assertEquals("invalid or expired code", e.message)
        }
    }
}
