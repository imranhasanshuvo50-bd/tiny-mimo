import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import '../services/ble_service.dart';
import '../widgets/status_card.dart';
import '../widgets/log_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final BleService _bleService = BleService.instance;
  late Timer _phoneTimeTimer;
  String _phoneTimeStr = "";
  BluetoothConnectionState _prevConnectionState = BluetoothConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _prevConnectionState = _bleService.connectionState;
    _bleService.addListener(_onConnectionChanged);
    _updatePhoneTime();
    _phoneTimeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updatePhoneTime();
      }
    });

    // Request initial status on connection
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_bleService.connectionState == BluetoothConnectionState.connected) {
        _bleService.writeCommand("STATUS");
      }
    });
  }

  @override
  void dispose() {
    _bleService.removeListener(_onConnectionChanged);
    _phoneTimeTimer.cancel();
    super.dispose();
  }

  void _onConnectionChanged() {
    final currentState = _bleService.connectionState;
    if (_prevConnectionState == BluetoothConnectionState.connected &&
        currentState == BluetoothConnectionState.disconnected &&
        mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/scan', (route) => false);
    }
    _prevConnectionState = currentState;
  }

  void _updatePhoneTime() {
    setState(() {
      _phoneTimeStr = DateFormat('yyyy-MM-dd hh:mm:ss a').format(DateTime.now());
    });
  }

  Color _getConnectionColor(BluetoothConnectionState state) {
    switch (state) {
      case BluetoothConnectionState.connected:
        return const Color(0xFF00FFCC);
      case BluetoothConnectionState.connecting:
        return const Color(0xFFFFB300);
      default:
        return const Color(0xFFFF3366);
    }
  }

  String _getConnectionText(BluetoothConnectionState state) {
    switch (state) {
      case BluetoothConnectionState.connected:
        return "Connected";
      case BluetoothConnectionState.connecting:
        return "Connecting...";
      default:
        return "Disconnected";
    }
  }

  Widget _buildTimePanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E), width: 1.2),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, color: Color(0xFF00FFCC), size: 20),
              const SizedBox(width: 8),
              const Text(
                "Time Telemetry",
                style: TextStyle(
                  color: Color(0xFF8B8B9E),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: _bleService,
                builder: (context, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _bleService.autoTimeSync
                          ? const Color(0xFF00FFCC).withOpacity(0.1)
                          : const Color(0xFF2E2E3E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _bleService.autoTimeSync ? "Auto Sync: ON" : "Auto Sync: OFF",
                      style: TextStyle(
                        color: _bleService.autoTimeSync
                            ? const Color(0xFF00FFCC)
                            : const Color(0xFF8B8B9E),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const Divider(color: Color(0xFF2E2E3E), height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Phone Time",
                    style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _phoneTimeStr,
                    style: const TextStyle(
                      color: Color(0xFFF1F1F8),
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    "Robot Time",
                    style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  ListenableBuilder(
                    listenable: _bleService,
                    builder: (context, _) {
                      return Text(
                        _bleService.robotStatus.robotTime,
                        style: const TextStyle(
                          color: Color(0xFFFFB300),
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Sync Telemetry Info
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F1A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListenableBuilder(
              listenable: _bleService,
              builder: (context, _) {
                final lastTimeStr = _bleService.lastSyncTime != null
                    ? DateFormat('HH:mm:ss').format(_bleService.lastSyncTime!)
                    : "Never";
                
                Color statusColor = const Color(0xFF8B8B9E);
                if (_bleService.lastSyncResult == "Success") {
                  statusColor = const Color(0xFF00FFCC);
                } else if (_bleService.lastSyncResult.startsWith("Failed")) {
                  statusColor = const Color(0xFFFF3366);
                } else if (_bleService.lastSyncResult.startsWith("Waiting")) {
                  statusColor = const Color(0xFFFFB300);
                }

                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Last Sync Value:",
                          style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 11),
                        ),
                        Text(
                          _bleService.lastSyncValue,
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Courier'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Last Sync Status:",
                          style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 11),
                        ),
                        Text(
                          _bleService.lastSyncResult,
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Last Sync Clock:",
                          style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 11),
                        ),
                        Text(
                          lastTimeStr,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryGrid() {
    return ListenableBuilder(
      listenable: _bleService,
      builder: (context, _) {
        final status = _bleService.robotStatus;
        
        final batteryVal = "${status.batteryPercentage}%";
        final batteryColor = status.batteryPercentage > 50
            ? const Color(0xFF00FFCC)
            : (status.batteryPercentage > 20 ? const Color(0xFFFFB300) : const Color(0xFFFF3366));

        return StatusCard(
          icon: Icons.battery_std,
          label: "Battery Level",
          value: batteryVal,
          color: batteryColor,
        );
      },
    );
  }

  Widget _buildRobotControlPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E), width: 1.2),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sports_esports, color: Color(0xFF00FFCC), size: 20),
              const SizedBox(width: 8),
              Text(
                "Robot Control Panel",
                style: TextStyle(
                  color: Color(0xFF8B8B9E),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF2E2E3E), height: 20),
          
          // Row of main buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCommandButton(
                icon: Icons.sync,
                label: "Sync Time",
                onPressed: () => _bleService.syncTime(),
              ),
              _buildCommandButton(
                icon: Icons.analytics,
                label: "Get Status",
                onPressed: () => _bleService.writeCommand("STATUS"),
              ),
              _buildCommandButton(
                icon: Icons.pets,
                label: "Pet Robot",
                onPressed: () => _bleService.writeCommand("PET"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSyncConfiguration() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E), width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListenableBuilder(
        listenable: _bleService,
        builder: (context, _) {
          return Column(
            children: [
              SwitchListTile(
                title: const Text(
                  "Auto Time Sync",
                  style: TextStyle(color: Color(0xFFF1F1F8), fontSize: 14, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  "Sends yyyy-mm-dd HH:mm:ss every 3m",
                  style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 11),
                ),
                activeColor: const Color(0xFF00FFCC),
                activeTrackColor: const Color(0xFF00FFCC).withOpacity(0.2),
                inactiveThumbColor: const Color(0xFF8B8B9E),
                inactiveTrackColor: const Color(0xFF2E2E3E),
                value: _bleService.autoTimeSync,
                onChanged: (val) => _bleService.setAutoTimeSync(val),
              ),
              const Divider(color: Color(0xFF2E2E3E), height: 8),
              SwitchListTile(
                title: const Text(
                  "Background Sync (Android)",
                  style: TextStyle(color: Color(0xFFF1F1F8), fontSize: 14, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  "Keeps connection running in background",
                  style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 11),
                ),
                activeColor: const Color(0xFF00FFCC),
                activeTrackColor: const Color(0xFF00FFCC).withOpacity(0.2),
                inactiveThumbColor: const Color(0xFF8B8B9E),
                inactiveTrackColor: const Color(0xFF2E2E3E),
                value: _bleService.backgroundSync,
                onChanged: (val) => _bleService.setBackgroundSync(val),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCommandButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2E2E3E),
        foregroundColor: const Color(0xFFF1F1F8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      icon: Icon(icon, size: 16, color: const Color(0xFF00FFCC)),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C12),
      appBar: AppBar(
        title: const Text(
          "Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.bluetooth, color: Color(0xFF00FFCC)),
          tooltip: "Manage Connection",
          onPressed: () {
            Navigator.pushNamedAndRemoveUntil(context, '/scan', (route) => false);
          },
        ),
        actions: [
          // Connection state pill
          ListenableBuilder(
            listenable: _bleService,
            builder: (context, _) {
              final color = _getConnectionColor(_bleService.connectionState);
              final text = _getConnectionText(_bleService.connectionState);
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      text,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: Colors.redAccent),
            tooltip: "Disconnect",
            onPressed: () async {
              await _bleService.disconnect();
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTimePanel(),
              const SizedBox(height: 16),
              _buildTelemetryGrid(),
              const SizedBox(height: 16),
              _buildRobotControlPanel(),
              const SizedBox(height: 16),
              _buildSyncConfiguration(),
              const SizedBox(height: 16),
              const LogPanel(maxLines: 8),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1E1E2E),
        selectedItemColor: const Color(0xFF00FFCC),
        unselectedItemColor: const Color(0xFF8B8B9E),
        currentIndex: 0,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.timer),
            label: "Prayers",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule),
            label: "Manual Sync",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Debug Logs",
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            Navigator.pushNamed(context, '/prayers');
          } else if (index == 2) {
            Navigator.pushNamed(context, '/time');
          } else if (index == 3) {
            Navigator.pushNamed(context, '/settings');
          }
        },
      ),
    );
  }
}
