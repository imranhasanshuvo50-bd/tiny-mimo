import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/robot_status.dart';

class BleService extends ChangeNotifier with WidgetsBindingObserver {
  // BLE UUID Constants
  static const String serviceUuidStr = "b0b00001-1234-5678-9999-abcdef000001";
  static const String rxUuidStr = "b0b00002-1234-5678-9999-abcdef000002";
  static const String txUuidStr = "b0b00003-1234-5678-9999-abcdef000003";

  static final Guid serviceGuid = Guid(serviceUuidStr);
  static final Guid rxGuid = Guid(rxUuidStr);
  static final Guid txGuid = Guid(txUuidStr);

  static const String channelName = "com.example.tiny_mimi/background_sync";
  static const MethodChannel _platform = MethodChannel(channelName);

  // Singleton instance
  static final BleService instance = BleService._();

  BleService._() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  late SharedPreferences _prefs;
  final RobotStatus robotStatus = RobotStatus();

  // State Variables
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? rxCharacteristic;
  BluetoothCharacteristic? txCharacteristic;
  
  List<ScanResult> _scanResults = [];
  List<ScanResult> get scanResults => _scanResults;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  BluetoothConnectionState get connectionState => _connectionState;

  bool _showAllDevices = false;
  bool get showAllDevices => _showAllDevices;

  bool _autoTimeSync = true;
  bool get autoTimeSync => _autoTimeSync;

  bool _backgroundSync = false;
  bool get backgroundSync => _backgroundSync;

  String _lastSyncValue = "N/A";
  String get lastSyncValue => _lastSyncValue;

  String _lastSyncResult = "No sync yet";
  String get lastSyncResult => _lastSyncResult;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  final List<String> _logs = [];
  List<String> get logs => _logs;

  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  bool _userDisconnected = false;
  bool _isReconnecting = false;
  Timer? _syncTimer;
  StreamSubscription? _txSubscription;
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _scanSubscription;

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _autoTimeSync = _prefs.getBool('auto_time_sync') ?? true;
    _backgroundSync = _prefs.getBool('background_sync') ?? false;
    _lastSyncValue = _prefs.getString('last_sync_value') ?? "N/A";
    _lastSyncResult = _prefs.getString('last_sync_result') ?? "No sync yet";
    final lastSyncTimeStr = _prefs.getString('last_sync_time');
    if (lastSyncTimeStr != null) {
      _lastSyncTime = DateTime.tryParse(lastSyncTimeStr);
    }
    
    // Listen to adapter state
    FlutterBluePlus.adapterState.listen((state) {
      addLog("Bluetooth Adapter State: $state");
      if (state == BluetoothAdapterState.on) {
        _attemptAutoReconnect();
      } else {
        _handleDisconnection();
      }
    });

    // Start auto-reconnect if adapter is already on
    if (await FlutterBluePlus.isSupported) {
      if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
        _attemptAutoReconnect();
      }
    }
  }

  void addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final formattedLog = "[$timestamp] $message";
    _logs.add(formattedLog);
    if (_logs.length > 200) {
      _logs.removeAt(0);
    }
    _logController.add(formattedLog);
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  // App Lifecycle callback
  bool _isAppDetached = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    addLog("App lifecycle changed: $state");
    if (state == AppLifecycleState.resumed) {
      _isAppDetached = false;
      if (connectionState == BluetoothConnectionState.connected && _autoTimeSync) {
        addLog("App resumed. Triggering automatic time sync...");
        syncTime();
      } else if (connectionState == BluetoothConnectionState.disconnected) {
        _attemptAutoReconnect();
      }
    } else if (state == AppLifecycleState.detached) {
      _isAppDetached = true;
      addLog("App detaching/exiting. Disconnecting BLE...");
      disconnect(isUserAction: false);
    }
  }

  // Permissions Request helper
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = {};
    
    if (defaultTargetPlatform == TargetPlatform.android) {
      statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.notification,
      ].request();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      statuses = await [
        Permission.bluetooth,
      ].request();
    }

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted && permission != Permission.locationWhenInUse) {
        // Location is not strictly required on Android 12+ if scanning with neverForLocation,
        // but we still request it. We won't block if location fails on newer Android.
        allGranted = false;
      }
    });

    addLog("Permissions status: $statuses");
    return allGranted;
  }

  // Toggle debug filter
  void toggleShowAllDevices(bool value) {
    _showAllDevices = value;
    notifyListeners();
  }

  // BLE Scan
  Future<void> startScan() async {
    if (_isScanning) {
      addLog("Scan is already active.");
      return;
    }
    final hasPermissions = await requestPermissions();
    if (!hasPermissions) {
      addLog("Error: Missing Bluetooth permissions for scanning.");
      return;
    }

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      addLog("Error: Bluetooth is turned off.");
      return;
    }

    _scanResults.clear();
    _isScanning = true;
    notifyListeners();

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      _scanResults = results;
      notifyListeners();
    }, onError: (e) {
      addLog("Scan Error: $e");
    });

    try {
      addLog("Starting BLE Scan...");
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      addLog("Failed to start scan: $e");
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      addLog("Failed to stop scan: $e");
    }
    _isScanning = false;
    notifyListeners();
  }

  void _listenToConnectionState(BluetoothDevice device) {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = device.connectionState.listen((state) {
      _connectionState = state;
      notifyListeners();
      if (state == BluetoothConnectionState.connected) {
        addLog("BLE Status: Connected");
        _setupConnectedDevice(device);
      } else if (state == BluetoothConnectionState.disconnected) {
        addLog("BLE Status: Disconnected");
        _handleDisconnection();
      }
    });
  }

  // Connect to Device
  Future<void> connect(BluetoothDevice device) async {
    _userDisconnected = false;
    addLog("Connecting to ${device.platformName.isEmpty ? 'Unknown' : device.platformName} (${device.remoteId})...");
    
    _listenToConnectionState(device);

    if (_isScanning) {
      addLog("Stopping scan before connecting...");
      await stopScan();
    }

    try {
      // Bypassed device.createBond() on Android to prevent getting stuck in pairing requests
      // since the ESP32 firmware is configured for open (non-bonded) UART communication.
      await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);
    } catch (e) {
      addLog("Connection failed: $e");
      try {
        await device.disconnect();
      } catch (_) {}
      _handleDisconnection();
      rethrow;
    }
  }

  Future<void> _setupConnectedDevice(BluetoothDevice device) async {
    if (connectedDevice == device && rxCharacteristic != null && txCharacteristic != null) {
      addLog("Device is already set up.");
      return;
    }
    connectedDevice = device;
    robotStatus.isConnected = true;
    
    // Save last connected MAC
    await _prefs.setString('last_connected_device_id', device.remoteId.str);
    
    try {
      // Discover Services with a 5-second timeout to avoid hangs
      addLog("Discovering services...");
      List<BluetoothService> services = await device.discoverServices()
          .timeout(const Duration(seconds: 5));
      
      for (var service in services) {
        if (service.uuid == serviceGuid) {
          for (var char in service.characteristics) {
            if (char.uuid == rxGuid) {
              rxCharacteristic = char;
              addLog("Found RX Write Characteristic: ${char.uuid}");
            } else if (char.uuid == txGuid) {
              txCharacteristic = char;
              addLog("Found TX Notify Characteristic: ${char.uuid}");
            }
          }
        }
      }

      if (txCharacteristic != null) {
        await txCharacteristic!.setNotifyValue(true);
        _txSubscription?.cancel();
        _txSubscription = txCharacteristic!.onValueReceived.listen((value) {
          final decoded = utf8.decode(value);
          addLog("[RX] $decoded");
          robotStatus.parseMessage(decoded);
          
          if (decoded.trim().toUpperCase().startsWith("TIME OK")) {
            _updateSyncResult(true, "Success");
          }
          notifyListeners();
        });
        addLog("Subscribed to TX Notify Characteristic");
      }

      if (rxCharacteristic == null) {
        addLog("Warning: RX Characteristic not found!");
      }

      // Trigger immediate Time Sync if Auto Sync is ON
      if (_autoTimeSync) {
        addLog("Auto Time Sync is ON. Sending initial time sync...");
        syncTime();
      }
      
      // Start periodic time sync every 3 minutes
      _startSyncTimer();

      // Trigger background native service if background sync is enabled
      if (_backgroundSync && defaultTargetPlatform == TargetPlatform.android) {
        _triggerNativeForegroundService(true);
      }
    } catch (e) {
      addLog("Failed to set up device characteristics: $e");
      disconnect(isUserAction: false);
    }
  }

  void _handleDisconnection() {
    _stopSyncTimer();
    _txSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    rxCharacteristic = null;
    txCharacteristic = null;
    connectedDevice = null;
    robotStatus.reset();
    _connectionState = BluetoothConnectionState.disconnected;
    notifyListeners();

    if (!_userDisconnected && !_isAppDetached) {
      _attemptAutoReconnect();
    }
  }

  Future<void> disconnect({bool isUserAction = true}) async {
    if (isUserAction) {
      _userDisconnected = true;
    }
    _stopSyncTimer();
    
    if (connectedDevice != null) {
      addLog("Disconnecting from device...");
      try {
        await connectedDevice!.disconnect();
      } catch (e) {
        addLog("Disconnect error: $e");
      }
    }
    
    if (_backgroundSync && defaultTargetPlatform == TargetPlatform.android) {
      _triggerNativeForegroundService(false);
    }
    
    _handleDisconnection();
  }

  // Attempt auto reconnect
  Future<void> _attemptAutoReconnect() async {
    if (_isReconnecting || connectedDevice != null || _userDisconnected) return;

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      addLog("Auto-reconnect skipped: Bluetooth adapter is OFF.");
      return;
    }
    
    final savedId = _prefs.getString('last_connected_device_id');
    if (savedId == null || savedId.isEmpty) {
      addLog("No last connected device ID stored. Skipping auto-reconnect.");
      return;
    }

    _isReconnecting = true;
    addLog("Attempting auto-reconnect to last connected device: $savedId...");

    // Check if the device is already connected according to the OS
    try {
      final connected = FlutterBluePlus.connectedDevices;
      BluetoothDevice? existing;
      for (var d in connected) {
        if (d.remoteId.str == savedId) {
          existing = d;
          break;
        }
      }
      if (existing != null) {
        addLog("Device $savedId is already connected to system. Attaching GATT...");
        _listenToConnectionState(existing);
        try {
          await existing.connect(timeout: const Duration(seconds: 5), autoConnect: false);
          _isReconnecting = false;
          return;
        } catch (e) {
          addLog("Failed to attach to existing device: $e");
        }
      }
    } catch (e) {
      addLog("Error checking already connected devices: $e");
    }
    
    int attempt = 0;
    while (connectedDevice == null && !_userDisconnected && !_isScanning && 
           FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      attempt++;
      addLog("Reconnection attempt #$attempt...");
      try {
        final device = BluetoothDevice.fromId(savedId);
        _listenToConnectionState(device);
        
        if (_isScanning) {
          addLog("Stopping scan before auto-reconnecting...");
          await stopScan();
        }
        await device.connect(timeout: const Duration(seconds: 8), autoConnect: false);
        break; // Connected successfully
      } catch (e) {
        addLog("Auto-reconnect attempt #$attempt failed: $e. Retrying in 3 seconds...");
        // Wait 3 seconds, but check periodically if we should stop waiting
        for (int i = 0; i < 3; i++) {
          if (_userDisconnected || _isScanning || 
              FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    _isReconnecting = false;
  }

  // Write BLE command
  Future<void> writeCommand(String command) async {
    if (rxCharacteristic == null) {
      addLog("Error: Cannot write command. RX Characteristic not available.");
      return;
    }

    try {
      addLog("[TX] $command");
      final bytes = utf8.encode(command);
      bool withoutResponse = rxCharacteristic!.properties.writeWithoutResponse;
      await rxCharacteristic!.write(bytes, withoutResponse: withoutResponse);
    } catch (e) {
      addLog("Write Error: $e");
      rethrow;
    }
  }

  // Time Sync logic
  Future<void> syncTime() async {
    final now = DateTime.now();
    final formattedTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final command = "TIME $formattedTime";

    _lastSyncValue = formattedTime;
    _prefs.setString('last_sync_value', _lastSyncValue);
    _lastSyncResult = "Waiting for robot response...";
    _prefs.setString('last_sync_result', _lastSyncResult);
    notifyListeners();

    try {
      await writeCommand(command);
      // Wait for a timeout in case robot doesn't respond with "TIME OK"
      Future.delayed(const Duration(seconds: 5), () {
        if (_lastSyncResult == "Waiting for robot response...") {
          _updateSyncResult(false, "Failed (No response)");
        }
      });
    } catch (e) {
      _updateSyncResult(false, "Failed ($e)");
    }
  }

  Future<void> manualSyncTime(DateTime pickedDateTime) async {
    final formattedTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(pickedDateTime);
    final command = "TIME $formattedTime";

    _lastSyncValue = formattedTime;
    _prefs.setString('last_sync_value', _lastSyncValue);
    _lastSyncResult = "Waiting for robot response...";
    _prefs.setString('last_sync_result', _lastSyncResult);
    notifyListeners();

    try {
      await writeCommand(command);
      Future.delayed(const Duration(seconds: 5), () {
        if (_lastSyncResult == "Waiting for robot response...") {
          _updateSyncResult(false, "Failed (No response)");
        }
      });
    } catch (e) {
      _updateSyncResult(false, "Failed ($e)");
    }
  }

  void _updateSyncResult(bool success, String result) {
    _lastSyncResult = result;
    _prefs.setString('last_sync_result', _lastSyncResult);
    if (success) {
      _lastSyncTime = DateTime.now();
      _prefs.setString('last_sync_time', _lastSyncTime!.toIso8601String());
    }
    notifyListeners();
  }

  // Toggles for user settings
  Future<void> setAutoTimeSync(bool value) async {
    _autoTimeSync = value;
    await _prefs.setBool('auto_time_sync', value);
    notifyListeners();
    if (value && connectionState == BluetoothConnectionState.connected) {
      syncTime();
    }
  }

  Future<void> setBackgroundSync(bool value) async {
    _backgroundSync = value;
    await _prefs.setBool('background_sync', value);
    notifyListeners();

    if (defaultTargetPlatform == TargetPlatform.android) {
      if (value && connectionState == BluetoothConnectionState.connected) {
        _triggerNativeForegroundService(true);
      } else {
        _triggerNativeForegroundService(false);
      }
    }
  }

  // Foreground Service triggers
  Future<void> _triggerNativeForegroundService(bool start) async {
    try {
      if (start) {
        addLog("Starting Android Foreground Service...");
        final result = await _platform.invokeMethod('startService');
        addLog("Foreground service start result: $result");
      } else {
        addLog("Stopping Android Foreground Service...");
        final result = await _platform.invokeMethod('stopService');
        addLog("Foreground service stop result: $result");
      }
    } catch (e) {
      addLog("Foreground Service Channel Error: $e");
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      if (connectionState == BluetoothConnectionState.connected && _autoTimeSync) {
        addLog("Periodic 3-minute sync trigger...");
        syncTime();
      }
    });
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSyncTimer();
    _txSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _logController.close();
    super.dispose();
  }
}
