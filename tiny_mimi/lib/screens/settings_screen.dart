import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BleService _bleService = BleService.instance;
  final TextEditingController _cmdController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendCustomCommand() {
    final cmd = _cmdController.text.trim();
    if (cmd.isNotEmpty) {
      _bleService.writeCommand(cmd);
      _cmdController.clear();
      FocusScope.of(context).unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Widget _buildCommandShortcut(String label, String command) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2E2E3E),
        foregroundColor: const Color(0xFF00FFCC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: () {
        _bleService.writeCommand(command);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      },
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Courier'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C12),
      appBar: AppBar(
        title: const Text("Debug Terminal", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Color(0xFFFF3366)),
            onPressed: () => _bleService.clearLogs(),
            tooltip: "Clear Logs",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Macro buttons
            const Text(
              "Quick Commands (API macros)",
              style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildCommandShortcut("HELP", "HELP"),
                _buildCommandShortcut("STATUS", "STATUS"),
                _buildCommandShortcut("PET", "PET"),
                _buildCommandShortcut("BAT 85", "BAT 85"),
                _buildCommandShortcut("SHOW FACE", "DISP 0"),
                _buildCommandShortcut("SHOW CLOCK", "DISP 1"),
                _buildCommandShortcut("SHOW PRAYER", "DISP 2"),
              ],
            ),
            const SizedBox(height: 20),
            
            // Console Terminal logs
            const Text(
              "Full Communication Terminal Log",
              style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F1A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2E2E3E), width: 1.5),
                ),
                padding: const EdgeInsets.all(12),
                child: ListenableBuilder(
                  listenable: _bleService,
                  builder: (context, _) {
                    final logs = _bleService.logs;
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                    if (logs.isEmpty) {
                      return const Center(
                        child: Text(
                          "Terminal is empty. Connect Mimo to view logs.",
                          style: TextStyle(color: Color(0xFF5A5A75), fontSize: 12),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        Color color = const Color(0xFFE2E2EC);
                        if (log.contains("[TX]")) {
                          color = const Color(0xFFFFB300);
                        } else if (log.contains("[RX]")) {
                          color = const Color(0xFF00FFCC);
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'Courier',
                              color: color,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Custom Command Sender
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cmdController,
                    decoration: InputDecoration(
                      hintText: "Enter ASCII Command...",
                      hintStyle: const TextStyle(color: Color(0xFF5A5A75), fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF1E1E2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2E2E3E)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF00FFCC)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Courier'),
                    onSubmitted: (_) => _sendCustomCommand(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFCC),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                  onPressed: _sendCustomCommand,
                  child: const Text(
                    "Send",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
