package com.melek.stargaleri

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Private alarm UI. No caller identity or conversation is shown on the lock screen. */
class WakeAlarmActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val check = object : Runnable {
        override fun run() {
            if (!WakeAlarmService.active) finish() else handler.postDelayed(this, 500)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_FULLSCREEN)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        if (!WakeAlarmService.active) { finish(); return }
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(Color.rgb(23, 25, 35))
        }
        layout.addView(TextView(this).apply {
            text = android.text.format.DateFormat.getTimeFormat(this@WakeAlarmActivity).format(java.util.Date())
            textSize = 48f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        })
        layout.addView(TextView(this).apply {
            text = "Hatırlatma"
            textSize = 32f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        })
        layout.addView(Button(this).apply {
            text = "Alarmı kapat"
            setOnClickListener {
                stopService(Intent(this@WakeAlarmActivity, WakeAlarmService::class.java))
                finish()
            }
        })
        setContentView(layout)
        handler.postDelayed(check, 500)
    }
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
