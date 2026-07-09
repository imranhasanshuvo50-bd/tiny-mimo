import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/ble_service.dart';

class TimeScreen extends StatefulWidget {
  const TimeScreen({super.key});

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> {
  final BleService _bleService = BleService.instance;
  
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
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
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
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
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _sendCustomTime() {
    final combinedDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
      0,
    );

    _bleService.manualSyncTime(combinedDateTime);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E1E2E),
        content: Text(
          "Sent TIME command: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(combinedDateTime)}",
          style: const TextStyle(color: Color(0xFF00FFCC), fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final formattedTime = "${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00";

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C12),
      appBar: AppBar(
        title: const Text("Manual Time Sync", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Set Custom Robot Clock",
              style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Date Picker Card
            Card(
              color: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF2E2E3E), width: 1.2),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FFCC).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.calendar_today, color: Color(0xFF00FFCC)),
                ),
                title: const Text("Date Settings", style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 12)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    formattedDate,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                trailing: TextButton(
                  onPressed: _pickDate,
                  child: const Text("Change", style: TextStyle(color: Color(0xFF00FFCC), fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Time Picker Card
            Card(
              color: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF2E2E3E), width: 1.2),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FFCC).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.access_time, color: Color(0xFF00FFCC)),
                ),
                title: const Text("Time Settings", style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 12)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    formattedTime,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                trailing: TextButton(
                  onPressed: _pickTime,
                  child: const Text("Change", style: TextStyle(color: Color(0xFF00FFCC), fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Preview Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E2E3E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Formatted Payload Preview", style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(
                    "TIME $formattedDate $formattedTime",
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontFamily: 'Courier',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            
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
                onPressed: _sendCustomTime,
                icon: const Icon(Icons.send),
                label: const Text(
                  "Override & Sync Custom Clock",
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
