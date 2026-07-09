package com.example.tiny_mimi

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

class MimoForegroundService : Service() {
    private val TAG = "MimoBgService"
    private val CHANNEL_ID = "tiny_mimo_bg_sync"

    // BLE UUID constants matching hardware specs
    private val SERVICE_UUID = UUID.fromString("b0b00001-1234-5678-9999-abcdef000001")
    private val RX_UUID = UUID.fromString("b0b00002-1234-5678-9999-abcdef000002")

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothGatt: BluetoothGatt? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null

    private val handler = Handler(Looper.getMainLooper())
    private var syncRunnable: Runnable? = null
    private var isStandaloneMode = false

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate: Initializing native Mimo background service")
        createNotificationChannel()
        initializeBluetooth()
    }

    private fun initializeBluetooth() {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val taskRemoved = intent?.getBooleanExtra("is_task_removed", false) ?: false
        Log.d(TAG, "onStartCommand: taskRemoved flag = $taskRemoved")

        // Read background sync enabled state directly from Flutter SharedPreferences
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val backgroundSyncEnabled = prefs.getBoolean("flutter.background_sync", false)
        Log.d(TAG, "onStartCommand: backgroundSyncEnabled (pref) = $backgroundSyncEnabled")

        showNotification()

        if (taskRemoved || backgroundSyncEnabled) {
            isStandaloneMode = true
            Log.d(TAG, "Standalone background mode activated. Starting native Kotlin BLE sync loop...")
            startNativeSyncLoop()
        }

        return START_STICKY
    }

    private fun showNotification() {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Tiny Mimo Robot")
            .setContentText("Tiny Mimo Robot connected — keeping time updated")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(1, notification)
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "onTaskRemoved: App swiped away from Recents!")
        
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val backgroundSyncEnabled = prefs.getBoolean("flutter.background_sync", false)

        if (backgroundSyncEnabled) {
            // Schedule service restart via AlarmManager
            val restartServiceIntent = Intent(applicationContext, this.javaClass).apply {
                putExtra("is_task_removed", true)
                setPackage(packageName)
            }
            val restartServicePendingIntent = PendingIntent.getService(
                applicationContext, 1, restartServiceIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerTime = android.os.SystemClock.elapsedRealtime() + 1000
            alarmManager.set(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerTime,
                restartServicePendingIntent
            )
            Log.d(TAG, "Scheduled AlarmManager restart in 1 second")
        }

        super.onTaskRemoved(rootIntent)
    }

    private fun startNativeSyncLoop() {
        stopNativeSyncLoop()

        syncRunnable = object : Runnable {
            override fun run() {
                Log.d(TAG, "Native sync trigger running...")
                connectAndSyncTime()
                // Run every 3 minutes
                handler.postDelayed(this, 3 * 60 * 1000)
            }
        }
        handler.post(syncRunnable!!)
    }

    private fun stopNativeSyncLoop() {
        syncRunnable?.let { handler.removeCallbacks(it) }
        disconnectGatt()
    }

    private fun connectAndSyncTime() {
        if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
            Log.e(TAG, "Bluetooth is disabled. Cannot start native sync.")
            return
        }

        val scanner = bluetoothAdapter!!.bluetoothLeScanner
        if (scanner == null) {
            Log.e(TAG, "BluetoothLeScanner not available.")
            return
        }

        val filter = ScanFilter.Builder()
            .setDeviceName("TinyMimoRobot")
            .build()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        var isScanning = true

        val scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                val device = result?.device
                if (device != null && isScanning) {
                    isScanning = false
                    try {
                        scanner.stopScan(this)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error stopping scan: ${e.message}")
                    }
                    Log.d(TAG, "Found TinyMimoRobot: ${device.address}. Connecting GATT...")
                    connectToDevice(device)
                }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "Scan failed: $errorCode")
            }
        }

        Log.d(TAG, "Scanning for TinyMimoRobot...")
        scanner.startScan(listOf(filter), settings, scanCallback)

        // Scan for 15 seconds max
        handler.postDelayed({
            if (isScanning) {
                isScanning = false
                try {
                    scanner.stopScan(scanCallback)
                } catch (e: Exception) {
                    Log.e(TAG, "Error stopping scan on timeout: ${e.message}")
                }
                Log.d(TAG, "Scan timeout. No device found.")
            }
        }, 15000)
    }

    private fun connectToDevice(device: BluetoothDevice) {
        disconnectGatt()

        bluetoothGatt = device.connectGatt(this, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    Log.d(TAG, "GATT Connected. Discovering services...")
                    gatt?.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    Log.d(TAG, "GATT Disconnected")
                    disconnectGatt()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    val service = gatt?.getService(SERVICE_UUID)
                    if (service != null) {
                        rxCharacteristic = service.getCharacteristic(RX_UUID)
                        if (rxCharacteristic != null) {
                            Log.d(TAG, "Found RX Characteristic. Writing TIME...")
                            sendTimePayload(gatt)
                        } else {
                            Log.e(TAG, "RX Characteristic not found")
                            disconnectGatt()
                        }
                    } else {
                        Log.e(TAG, "Service not found")
                        disconnectGatt()
                    }
                } else {
                    Log.e(TAG, "Services discovery failed: $status")
                    disconnectGatt()
                }
            }
        })
    }

    private fun sendTimePayload(gatt: BluetoothGatt) {
        val rxChar = rxCharacteristic ?: return
        val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        val timeStr = "TIME " + formatter.format(Date())

        Log.d(TAG, "Writing command: $timeStr")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(
                rxChar, 
                timeStr.toByteArray(Charsets.UTF_8), 
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            )
        } else {
            rxChar.value = timeStr.toByteArray(Charsets.UTF_8)
            rxChar.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            gatt.writeCharacteristic(rxChar)
        }

        // Keep connection open for 3 seconds to ensure write completes, then disconnect
        handler.postDelayed({
            Log.d(TAG, "Sync complete. Closing GATT connection.")
            disconnectGatt()
        }, 3000)
    }

    private fun disconnectGatt() {
        try {
            bluetoothGatt?.disconnect()
            bluetoothGatt?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing GATT: ${e.message}")
        }
        bluetoothGatt = null
        rxCharacteristic = null
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy: Stopping native background service")
        stopNativeSyncLoop()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Tiny Mimo Background Sync Channel",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }
}
