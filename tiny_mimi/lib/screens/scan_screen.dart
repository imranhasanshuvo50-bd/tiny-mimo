import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  late AnimationController _eyeController;
  final BleService _bleService = BleService.instance;
  bool _isConnectingDialogShow = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _eyeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    
    _bleService.addListener(_onConnectionChanged);
    
    // Auto scan or auto redirect on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_bleService.connectionState == BluetoothConnectionState.connected) {
        if (!_isNavigating && mounted) {
          _navigateToDashboard();
        }
      } else {
        _bleService.startScan();
      }
    });
  }

  @override
  void dispose() {
    _eyeController.dispose();
    _bleService.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (mounted) {
      setState(() {});
    }
    if (_bleService.connectionState == BluetoothConnectionState.connected && mounted && !_isNavigating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isNavigating) {
          if (_isConnectingDialogShow) {
            setState(() {
              _isConnectingDialogShow = false;
            });
          }
          _navigateToDashboard();
        }
      });
    }
  }

  void _navigateToDashboard() {
    _isNavigating = true;
    Navigator.pushReplacementNamed(context, '/dashboard');
  }

  Widget _buildRobotHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF2E2E3E), width: 1.5),
      ),
      child: Column(
        children: [
          // Cute Robot Eyes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _eyeController,
                builder: (context, child) {
                  double scaleY = 1.0;
                  if (_eyeController.value > 0.95) {
                    scaleY = 0.1; // Blink effect
                  }
                  return Row(
                    children: [
                      // Left Eye
                      Transform.scale(
                        scaleY: scaleY,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FFCC),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00FFCC).withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                      // Right Eye
                      Transform.scale(
                        scaleY: scaleY,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FFCC),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00FFCC).withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "TINY MIMO ROBOT",
            style: TextStyle(
              color: Color(0xFFF1F1F8),
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "BLE CONTROLLER APP",
            style: TextStyle(
              color: Color(0xFF8B8B9E),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            color: Colors.black.withOpacity(0.55),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2E2E3E), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FFCC).withOpacity(0.15),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Color(0xFF00FFCC),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Connecting to Mimo...",
                      style: TextStyle(
                        color: Color(0xFFF1F1F8),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Establishing secure BLE link",
                      style: TextStyle(
                        color: Color(0xFF8B8B9E),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E2E3E), width: 1),
                      ),
                      child: ListenableBuilder(
                        listenable: _bleService,
                        builder: (context, _) {
                          final logCount = _bleService.logs.length;
                          final lastLogs = _bleService.logs.skip(logCount > 4 ? logCount - 4 : 0).toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: lastLogs.isEmpty
                                ? [
                                    const Text(
                                      "Waiting for BLE logs...",
                                      style: TextStyle(color: Color(0xFF5A5A75), fontSize: 11, fontFamily: 'Courier'),
                                    )
                                  ]
                                : lastLogs.map((log) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                                      child: Text(
                                        log,
                                        style: const TextStyle(
                                          color: Color(0xFF00FFCC),
                                          fontSize: 10,
                                          fontFamily: 'Courier',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )).toList(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF3366),
                          ),
                          onPressed: () {
                            _bleService.stopScan();
                            _bleService.disconnect(isUserAction: true);
                            setState(() {
                              _isConnectingDialogShow = false;
                            });
                          },
                          child: const Text("Cancel"),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E2E3E),
                            foregroundColor: const Color(0xFF00FFCC),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(color: Color(0xFF00FFCC), width: 1),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            setState(() {
                              _isConnectingDialogShow = false;
                            });
                            _navigateToDashboard();
                          },
                          child: const Text(
                            "Skip to Dashboard",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C12),
      appBar: AppBar(
        title: const Text(
          "Connect Mimo",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.dashboard, color: Color(0xFF00FFCC)),
          tooltip: "Go to Dashboard",
          onPressed: () {
            _navigateToDashboard();
          },
        ),
        actions: [
          ListenableBuilder(
            listenable: _bleService,
            builder: (context, _) {
              return IconButton(
                icon: Icon(
                  _bleService.isScanning ? Icons.stop : Icons.refresh,
                  color: const Color(0xFF00FFCC),
                ),
                onPressed: () {
                  if (_bleService.isScanning) {
                    _bleService.stopScan();
                  } else {
                    _bleService.startScan();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRobotHeader(),
            const SizedBox(height: 20),
            
            // Bluetooth status indicator if off
            StreamBuilder<BluetoothAdapterState>(
              stream: FlutterBluePlus.adapterState,
              initialData: BluetoothAdapterState.unknown,
              builder: (context, snapshot) {
                final state = snapshot.data;
                if (state != BluetoothAdapterState.on) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A1F1F),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bluetooth_disabled, color: Colors.redAccent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            state == BluetoothAdapterState.off
                                ? "Bluetooth is currently turned OFF. Please enable Bluetooth to scan."
                                : "Bluetooth adaptor state: $state",
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            // Scan Control Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Devices Nearby",
                  style: TextStyle(
                    color: Color(0xFFF1F1F8),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ListenableBuilder(
                  listenable: _bleService,
                  builder: (context, _) {
                    return Row(
                      children: [
                        const Text(
                          "Show All",
                          style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 12),
                        ),
                        Switch(
                          value: _bleService.showAllDevices,
                          activeColor: const Color(0xFF00FFCC),
                          activeTrackColor: const Color(0xFF00FFCC).withOpacity(0.2),
                          inactiveThumbColor: const Color(0xFF8B8B9E),
                          inactiveTrackColor: const Color(0xFF2E2E3E),
                          onChanged: (val) {
                            _bleService.toggleShowAllDevices(val);
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Scanning state loader
            ListenableBuilder(
              listenable: _bleService,
              builder: (context, _) {
                if (_bleService.isScanning) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: LinearProgressIndicator(
                      backgroundColor: Color(0xFF1E1E2E),
                      color: Color(0xFF00FFCC),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            
            // Device list
            Expanded(
              child: ListenableBuilder(
                listenable: _bleService,
                builder: (context, _) {
                  final results = _bleService.scanResults;
                  final filtered = results.where((r) {
                    if (_bleService.showAllDevices) return true;
                    // Only show device named "TinyMimiRobot"
                    return r.device.platformName == "TinyMimiRobot";
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.radar,
                            size: 48,
                            color: Color(0xFF2E2E3E),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _bleService.isScanning
                                ? "Searching for TinyMimiRobot..."
                                : "No devices found.",
                            style: const TextStyle(
                              color: Color(0xFF5A5A75),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final result = filtered[index];
                      final name = result.device.platformName.isEmpty
                          ? "Unknown Device"
                          : result.device.platformName;
                      final isMimo = name == "TinyMimiRobot";

                      return Card(
                        color: const Color(0xFF1E1E2E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isMimo
                                ? const Color(0xFF00FFCC).withOpacity(0.3)
                                : const Color(0xFF2E2E3E),
                            width: 1.2,
                          ),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (isMimo ? const Color(0xFF00FFCC) : const Color(0xFF8B8B9E))
                                  .withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isMimo ? Icons.smart_toy : Icons.bluetooth,
                              color: isMimo ? const Color(0xFF00FFCC) : const Color(0xFF8B8B9E),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              color: Color(0xFFF1F1F8),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                "ID: ${result.device.remoteId}",
                                style: const TextStyle(
                                  color: Color(0xFF8B8B9E),
                                  fontSize: 12,
                                  fontFamily: 'Courier',
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "RSSI: ${result.rssi} dBm",
                                style: TextStyle(
                                  color: result.rssi > -70 ? const Color(0xFF00FFCC) : const Color(0xFFFFB300),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isMimo
                                  ? const Color(0xFF00FFCC)
                                  : const Color(0xFF2E2E3E),
                              foregroundColor: isMimo ? Colors.black : Colors.white70,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: () async {
                              _bleService.stopScan();
                              setState(() {
                                _isConnectingDialogShow = true;
                              });

                              // Settle the BLE adapter after stopping scan
                              await Future.delayed(const Duration(milliseconds: 500));

                              try {
                                await _bleService.connect(result.device);
                              } catch (e) {
                                if (context.mounted) {
                                  setState(() {
                                    _isConnectingDialogShow = false;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF3A1F1F),
                                      content: Text(
                                        "Connection failed: $e",
                                        style: const TextStyle(color: Colors.redAccent),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text(
                              "Connect",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      if (_isConnectingDialogShow || _bleService.connectionState == BluetoothConnectionState.connecting)
        _buildLoadingOverlay(),
    ],
  ),
);
}
}
