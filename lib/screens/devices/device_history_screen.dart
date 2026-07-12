import 'package:flutter/material.dart';

/// DeviceHistoryScreen — Lịch sử hoạt động của MỘT thiết bị (mock timeline tĩnh).
class DeviceHistoryScreen extends StatelessWidget {
  final String mac;
  final String deviceName;
  const DeviceHistoryScreen({super.key, required this.mac, required this.deviceName});

  static const Color tkGreen = Color(0xFF00A651);

  // Mock nhật ký: {time, when, on(true=Bật), by}
  static const List<Map<String, dynamic>> _logs = [
    {'time': '10:30', 'when': 'Hôm nay', 'on': true, 'by': 'tinhkt.ipca'},
    {'time': '09:15', 'when': 'Hôm nay', 'on': false, 'by': 'Home Assistant'},
    {'time': '08:00', 'when': 'Hôm qua', 'on': false, 'by': 'Ngữ cảnh: Rời khỏi nhà'},
    {'time': '18:45', 'when': 'Hôm qua', 'on': true, 'by': 'Lịch trình 18:45'},
    {'time': '07:00', 'when': '2 ngày trước', 'on': true, 'by': 'tinhkt.ipca'},
  ];

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color lineColor = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Lịch sử hoạt động', style: TextStyle(fontSize: 16)),
          Text(deviceName, style: TextStyle(fontSize: 12, color: textSub, fontWeight: FontWeight.normal)),
        ]),
        backgroundColor: cardColor,
        foregroundColor: textMain,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _logs.length,
          itemBuilder: (context, index) {
            final log = _logs[index];
            final bool on = log['on'] == true;
            final Color dotColor = on ? tkGreen : Colors.redAccent;
            final bool isLast = index == _logs.length - 1;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cột timeline: chấm tròn + đường nối
                  Column(
                    children: [
                      Container(width: 14, height: 14, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle, border: Border.all(color: dotColor.withValues(alpha: 0.3), width: 3))),
                      if (!isLast) Expanded(child: Container(width: 2, color: lineColor)),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Nội dung sự kiện
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(on ? Icons.power_settings_new : Icons.power_off, color: dotColor, size: 18),
                              const SizedBox(width: 8),
                              Text(on ? 'Bật thiết bị' : 'Tắt thiết bị', style: TextStyle(color: dotColor, fontWeight: FontWeight.bold, fontSize: 15)),
                              const Spacer(),
                              Text('${log['time']} · ${log['when']}', style: TextStyle(color: textSub, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Bởi: ${log['by']}', style: TextStyle(color: textMain.withValues(alpha: 0.8), fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
