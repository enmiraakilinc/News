package com.melek.stargaleri

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.*
import android.view.Gravity
import android.view.WindowManager
import android.widget.*
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

/** Only opens a private ringing UI. Camera/microphone never start here. */
class IncomingCallActivity : Activity() {
    private val handler=Handler(Looper.getMainLooper())
    private var listener:ListenerRegistration?=null
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if(Build.VERSION.SDK_INT>=27){setShowWhenLocked(true);setTurnScreenOn(true)}
        else window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        val id=intent.getStringExtra("callId")
        val uid=intent.getStringExtra("uid")
        val nonce=intent.getStringExtra("nonce")
        val created=intent.getLongExtra("created",0)
        val prefs=getSharedPreferences("call_notifications",Context.MODE_PRIVATE)
        val local=getSharedPreferences("FlutterSharedPreferences",Context.MODE_PRIVATE)
        if(id==null||!Regex("^[A-Za-z0-9]{20}$").matches(id)||uid!=FirebaseAuth.getInstance().currentUser?.uid||nonce==null||prefs.getString("nonce_$id",null)!=nonce||!VoiceCallBridge.enabled(this,intent.getBooleanExtra("video",false))||System.currentTimeMillis()-created !in 0..45000){finish();return}
        val layout=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER;setPadding(48,48,48,48);setBackgroundColor(Color.rgb(23,25,35))}
        layout.addView(TextView(this).apply{text=if(intent.getBooleanExtra("video",false))"Gelen görüntülü arama" else "Gelen sesli arama";textSize=30f;setTextColor(Color.WHITE);gravity=Gravity.CENTER})
        val answer=Button(this).apply{text="Yanıtla"}
        val decline=Button(this).apply{text="Reddet"}
        layout.addView(answer);layout.addView(decline);setContentView(layout)
        answer.setOnClickListener {
            if(prefs.getString("nonce_$id",null)!=nonce){finish();return@setOnClickListener}
            answer.isEnabled=false;decline.isEnabled=false
            startActivity(Intent(this,MainActivity::class.java).setAction(VoiceCallBridge.ANSWER).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("callId",id).putExtra("uid",uid).putExtra("nonce",nonce))
            finish()
        }
        decline.setOnClickListener {
            prefs.edit().remove("nonce_$id").apply()
            (getSystemService(Context.NOTIFICATION_SERVICE)as NotificationManager).cancel(VoiceCallBridge.notificationId(id))
            sendBroadcast(Intent(this,VoiceCallDeclineReceiver::class.java).putExtra("callId",id).putExtra("uid",uid))
            finish()
        }
        listener=FirebaseFirestore.getInstance().document("voiceCalls/$id").addSnapshotListener{doc,_ ->
            if(doc!=null&&(!doc.exists()||doc.getString("state")!="ringing"))finish()
        }
        handler.postDelayed({finish()},(created+45000-System.currentTimeMillis()).coerceIn(1,45000))
        val check=object:Runnable {override fun run(){
            if(FirebaseAuth.getInstance().currentUser?.uid!=uid||prefs.getString("nonce_$id",null)!=nonce||!VoiceCallBridge.enabled(this@IncomingCallActivity,intent.getBooleanExtra("video",false)))finish()
            else handler.postDelayed(this,500)
        }}
        handler.postDelayed(check,500)
    }
    override fun onDestroy(){handler.removeCallbacksAndMessages(null);listener?.remove();super.onDestroy()}
}
