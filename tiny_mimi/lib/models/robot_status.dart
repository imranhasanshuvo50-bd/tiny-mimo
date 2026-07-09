class RobotStatus {
  int batteryPercentage = 0;
  String robotTime = "Unknown";
  bool isConnected = false;
  DateTime? lastSyncTime;
  String lastSyncResult = "No sync yet";

  Map<String, String> prayerTimes = {
    'Fajr': '04:20',
    'Dhuhr': '12:10',
    'Asr': '15:45',
    'Maghrib': '18:35',
    'Isha': '20:00',
  };

  void parseMessage(String msg) {
    final cleanMsg = msg.trim().toUpperCase();
    if (cleanMsg == 'CONNECTED') {
      isConnected = true;
    } else if (cleanMsg.contains('BAT ')) {
      final match = RegExp(r'\d+').firstMatch(cleanMsg);
      if (match != null) {
        batteryPercentage = int.tryParse(match.group(0)!) ?? batteryPercentage;
      }
    } else if (cleanMsg.startsWith('TIME OK')) {
      lastSyncTime = DateTime.now();
      lastSyncResult = "Success";
    } else if (cleanMsg == 'PRAYER SAVED') {
      // Just feedback that prayer times are saved
    } else if (cleanMsg.startsWith('FAJR ')) {
      prayerTimes['Fajr'] = msg.substring(5).trim();
    } else if (cleanMsg.startsWith('DHUHR ')) {
      prayerTimes['Dhuhr'] = msg.substring(6).trim();
    } else if (cleanMsg.startsWith('ASR ')) {
      prayerTimes['Asr'] = msg.substring(4).trim();
    } else if (cleanMsg.startsWith('MAGHRIB ')) {
      prayerTimes['Maghrib'] = msg.substring(8).trim();
    } else if (cleanMsg.startsWith('ISHA ')) {
      prayerTimes['Isha'] = msg.substring(5).trim();
    } else if (cleanMsg.startsWith('TIME ')) {
      robotTime = msg.substring(5).trim();
    }
  }

  void reset() {
    isConnected = false;
    batteryPercentage = 0;
    robotTime = "Unknown";
  }
}
