import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ble_service.dart';

class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  final BleService _bleService = BleService.instance;

  String _fajr = "04:20";
  String _dhuhr = "12:10";
  String _asr = "15:45";
  String _maghrib = "18:35";
  String _isha = "20:00";

  late SharedPreferences _prefs;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedPrayers();
  }

  Future<void> _loadSavedPrayers() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _fajr = _prefs.getString('prayer_fajr') ?? "04:20";
      _dhuhr = _prefs.getString('prayer_dhuhr') ?? "12:10";
      _asr = _prefs.getString('prayer_asr') ?? "15:45";
      _maghrib = _prefs.getString('prayer_maghrib') ?? "18:35";
      _isha = _prefs.getString('prayer_isha') ?? "20:00";
      _isLoading = false;
    });
  }

  Future<void> _selectTime(String prayerKey, String currentValue) async {
    final timeParts = currentValue.split(':');
    final initialHour = int.tryParse(timeParts[0]) ?? 12;
    final initialMinute = int.tryParse(timeParts[1]) ?? 0;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00FFCC),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E2E),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0C0C12),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final hourStr = picked.hour.toString().padLeft(2, '0');
      final minStr = picked.minute.toString().padLeft(2, '0');
      final formattedTime = "$hourStr:$minStr";

      setState(() {
        if (prayerKey == 'Fajr') _fajr = formattedTime;
        if (prayerKey == 'Dhuhr') _dhuhr = formattedTime;
        if (prayerKey == 'Asr') _asr = formattedTime;
        if (prayerKey == 'Maghrib') _maghrib = formattedTime;
        if (prayerKey == 'Isha') _isha = formattedTime;
      });
    }
  }

  Future<void> _savePrayerTimes() async {
    await _prefs.setString('prayer_fajr', _fajr);
    await _prefs.setString('prayer_dhuhr', _dhuhr);
    await _prefs.setString('prayer_asr', _asr);
    await _prefs.setString('prayer_maghrib', _maghrib);
    await _prefs.setString('prayer_isha', _isha);

    final command = "PRAYER $_fajr $_dhuhr $_asr $_maghrib $_isha";

    try {
      await _bleService.writeCommand(command);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF1E1E2E),
            content: Text(
              "Saved & PRAYER command sent successfully!",
              style: TextStyle(color: Color(0xFF00FFCC), fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF3A1F1F),
            content: Text(
              "Error sending command: $e",
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        );
      }
    }
  }

  Widget _buildPrayerRow(String label, String value, IconData icon) {
    return Card(
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2E2E3E), width: 1.2),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00FFCC).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF00FFCC), size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFF1F1F8),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            InkWell(
              onTap: () => _selectTime(label, value),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F1A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2E2E3E)),
                ),
                child: Row(
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFFFFB300),
                        fontFamily: 'Courier',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit, color: Color(0xFF8B8B9E), size: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C12),
      appBar: AppBar(
        title: const Text("Prayer Schedules", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FFCC)))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        const SizedBox(height: 12),
                        const Text(
                          "Configure Prayer Alerts",
                          style: TextStyle(
                            color: Color(0xFF8B8B9E),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildPrayerRow("Fajr", _fajr, Icons.wb_twilight),
                        _buildPrayerRow("Dhuhr", _dhuhr, Icons.wb_sunny),
                        _buildPrayerRow("Asr", _asr, Icons.wb_sunny_outlined),
                        _buildPrayerRow("Maghrib", _maghrib, Icons.nights_stay),
                        _buildPrayerRow("Isha", _isha, Icons.bedtime),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FFCC),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 4,
                      ),
                      onPressed: _savePrayerTimes,
                      icon: const Icon(Icons.save, size: 20),
                      label: const Text(
                        "Save & Sync to Robot",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
