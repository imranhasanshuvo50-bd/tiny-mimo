import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class LogPanel extends StatefulWidget {
  final int maxLines;
  const LogPanel({super.key, this.maxLines = 15});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BleService.instance,
      builder: (context, _) {
        final logs = BleService.instance.logs;
        final displayLogs = logs.length > widget.maxLines
            ? logs.sublist(logs.length - widget.maxLines)
            : logs;

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF2E2E3E),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00FFCC),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Live BLE Console",
                        style: TextStyle(
                          color: Color(0xFF8B8B9E),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => BleService.instance.clearLogs(),
                    child: const Text(
                      "Clear",
                      style: TextStyle(
                        color: Color(0xFFFF3366),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF2E2E3E), height: 16),
              if (displayLogs.isEmpty)
                const SizedBox(
                  height: 100,
                  child: Center(
                    child: Text(
                      "No communication logs yet.",
                      style: TextStyle(
                        color: Color(0xFF5A5A75),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 110,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: displayLogs.length,
                    itemBuilder: (context, index) {
                      final log = displayLogs[index];
                      Color textColor = const Color(0xFFE2E2EC);
                      if (log.contains("[TX]")) {
                        textColor = const Color(0xFFFFB300); 
                      } else if (log.contains("[RX]")) {
                        textColor = const Color(0xFF00FFCC); 
                      }
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          log,
                          style: TextStyle(
                            fontFamily: 'Courier',
                            color: textColor,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
