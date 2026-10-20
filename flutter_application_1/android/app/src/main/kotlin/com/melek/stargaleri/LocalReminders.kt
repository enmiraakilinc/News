package com.melek.stargaleri

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

object LocalReminders {
    private fun prefs(context: Context)=context.getSharedPreferences("local_note_reminders",Context.MODE_PRIVATE)
    private fun manager(context: Context)=context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private fun valid(id: String)=Regex("^[a-f0-9-]{36}$").matches(id)
    private fun pending(context:Context,id:String)=PendingIntent.getBroadcast(context,0,
        Intent(context,NoteReminderReceiver::class.java).setAction("note_reminder").setData(Uri.parse("neural-note:$id")).putExtra("id",id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun allowed(context:Context)=Build.VERSION.SDK_INT<31 || manager(context).canScheduleExactAlarms()
    private fun schedule(context:Context,id:String,at:Long) {
        manager(context).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending(context,id))
    }
    fun consume(context:Context,id:String?):Boolean {
        if(id==null || !valid(id))return false
        val at=prefs(context).getLong(id,0)
        if(at==0L || at>System.currentTimeMillis()+5000 || at<System.currentTimeMillis()-86400000)return false
        return prefs(context).edit().remove(id).commit()
    }
    fun handle(context:Context,call:io.flutter.plugin.common.MethodCall,result:MethodChannel.Result) {
        try {
            when(call.method) {
                "canSchedule"->result.success(allowed(context))
                "settings"->{if(Build.VERSION.SDK_INT>=31)context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,Uri.parse("package:${context.packageName}")));result.success(null)}
                "cancel"->{val id=call.argument<String>("id");if(id!=null && valid(id)){manager(context).cancel(pending(context,id));prefs(context).edit().remove(id).apply()};result.success(null)}
                "schedule"->{val id=call.argument<String>("id");val at=call.argument<Number>("at")?.toLong()?:0
                    if(id==null || !valid(id) || at<=System.currentTimeMillis() || at>System.currentTimeMillis()+366L*86400000)throw IllegalArgumentException()
                    if(!allowed(context))throw SecurityException()
                    schedule(context,id,at);prefs(context).edit().putLong(id,at).commit();result.success(null)}
                else->result.notImplemented()
            }
        }catch(_:Exception){result.error("reminder_failed","Hatırlatıcı kurulamadı. Alarm iznini kontrol et.",null)}
    }
    fun restore(context:Context){if(!allowed(context))return;for((id,value)in prefs(context).all){if(valid(id) && value is Long && value>System.currentTimeMillis()){try{schedule(context,id,value)}catch(_:Exception){}}}}
}

class NoteReminderReceiver:BroadcastReceiver(){
    override fun onReceive(context:Context,intent:Intent){
        if(intent.action!= "note_reminder")return
        val notifications=context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        if(Build.VERSION.SDK_INT>=24 && !notifications.areNotificationsEnabled())return
        val alarm=Intent(context,WakeAlarmService::class.java).setAction("local").putExtra("reminderId",intent.getStringExtra("id"))
        try{if(Build.VERSION.SDK_INT>=26)context.startForegroundService(alarm)else context.startService(alarm)}catch(_:Exception){}
    }
}
class NoteReminderBootReceiver:BroadcastReceiver(){
    override fun onReceive(context:Context,intent:Intent){if(intent.action==Intent.ACTION_BOOT_COMPLETED || intent.action==Intent.ACTION_MY_PACKAGE_REPLACED)LocalReminders.restore(context)}
}
