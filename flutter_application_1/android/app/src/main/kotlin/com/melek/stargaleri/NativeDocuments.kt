package com.melek.stargaleri

import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL
import java.time.Instant
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.net.ssl.HttpsURLConnection

/** Native incoming-call/alarm checks use the same authenticated store as Flutter. */
object NativeDocuments {
    private val executor = Executors.newFixedThreadPool(3)
    data class Snapshot(val data: Map<String, Any?>?) {
        fun get(key: String): Any? = data?.get(key)
        fun getBoolean(key: String): Boolean? = get(key) as? Boolean
        fun getString(key: String): String? = get(key) as? String
        fun exists() = data != null
    }
    fun interface Registration { fun remove() }
    fun document(path: String) = Reference(path)
    private fun request(route: String, body: JSONObject): JSONObject {
        val user = FirebaseAuth.getInstance().currentUser ?: error("Oturum gerekli.")
        val uid = user.uid
        val token = Tasks.await(user.getIdToken(false), 3, TimeUnit.SECONDS).token ?: error("Oturum gerekli.")
        val connection = URL("https://138.2.185.151$route").openConnection() as HttpsURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 2500
            connection.readTimeout = 3500
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.doOutput = true
            connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            if (connection.responseCode != 200) error("Sunucuya baglanilamadi.")
            val text = connection.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                val buffer = CharArray(4096)
                val output = StringBuilder()
                while (true) {
                    val count = reader.read(buffer)
                    if (count < 0) break
                    output.append(buffer, 0, count)
                    require(output.length <= 2 * 1024 * 1024)
                }
                output.toString()
            }
            check(FirebaseAuth.getInstance().currentUser?.uid == uid)
            return JSONObject(text)
        } finally { connection.disconnect() }
    }
    private fun decode(value: JSONObject): Any? = when {
        value.has("nullValue") -> null
        value.has("stringValue") -> value.getString("stringValue")
        value.has("booleanValue") -> value.getBoolean("booleanValue")
        value.has("integerValue") -> value.getString("integerValue").toLong()
        value.has("doubleValue") -> value.getDouble("doubleValue")
        value.has("timestampValue") -> Instant.parse(value.getString("timestampValue")).let { Timestamp(it.epochSecond,it.nano) }
        value.has("arrayValue") -> value.getJSONObject("arrayValue").optJSONArray("values")?.let { a -> List(a.length()) { decode(a.getJSONObject(it)) } } ?: emptyList<Any?>()
        value.has("mapValue") -> fields(value.getJSONObject("mapValue").optJSONObject("fields") ?: JSONObject())
        else -> error("Desteklenmeyen veri.")
    }
    private fun fields(objectValue: JSONObject): Map<String, Any?> =
        objectValue.keys().asSequence().associateWith { decode(objectValue.getJSONObject(it)) }
    class Reference(private val path: String) {
        init { require(path.length <= 1500 && path.split('/').size % 2 == 0 && !path.contains("..") && !path.contains("//")) }
        fun get(): Task<Snapshot> {
            if (!BuildConfig.POSTGRES_PRIMARY) return FirebaseFirestore.getInstance().document(path).get(Source.SERVER)
                .continueWith(executor) { result -> Snapshot(result.getResult(Exception::class.java).data) }
            return Tasks.call(executor) {
                val row = request("/v1/read", JSONObject().put("kind","document").put("path",path)).optJSONObject("row")
                Snapshot(row?.getJSONObject("document")?.optJSONObject("fields")?.let { fields(it) })
            }
        }
        fun update(values: Map<String, Any>): Task<*> {
            if (!BuildConfig.POSTGRES_PRIMARY) return FirebaseFirestore.getInstance().document(path).update(values)
            return Tasks.call(executor) {
                val encoded = JSONArray()
                for ((key,value) in values) {
                    val field = when {
                        value is String -> JSONObject().put("stringValue",value)
                        value is FieldValue && key == "endedAt" -> JSONObject().put("transformValue",JSONObject().put("operation","serverTimestamp"))
                        else -> error("Desteklenmeyen islem.")
                    }
                    encoded.put(JSONObject().put("field",JSONArray().put(key)).put("value",field))
                }
                val uid = FirebaseAuth.getInstance().currentUser?.uid ?: error("Oturum gerekli.")
                request("/v1/commit", JSONObject().put("requestId",UUID.randomUUID().toString())
                    .put("actorUid",uid).put("clientCode",2081)
                    .put("operations",JSONArray().put(JSONObject().put("type","update").put("path",path).put("fields",encoded))))
            }
        }
        fun addSnapshotListener(callback: (Snapshot?,Exception?) -> Unit): Registration {
            if (!BuildConfig.POSTGRES_PRIMARY) {
                val registration = FirebaseFirestore.getInstance().document(path).addSnapshotListener { value,error ->
                    callback(value?.let { Snapshot(it.data) },error)
                }
                return Registration { registration.remove() }
            }
            val handler = Handler(Looper.getMainLooper())
            var cancelled = false
            lateinit var poll: Runnable
            poll = Runnable {
                if (!cancelled) get().addOnCompleteListener { result ->
                    if (!cancelled) {
                        if (result.isSuccessful) callback(result.result,null) else callback(null,result.exception)
                        handler.postDelayed(poll,1000)
                    }
                }
            }
            handler.post(poll)
            return Registration { cancelled=true;handler.removeCallbacks(poll) }
        }
    }
}
