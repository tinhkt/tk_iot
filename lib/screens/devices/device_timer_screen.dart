import 'package:flutter/material.dart';

/// DeviceTimerScreen — Hẹn giờ & Lịch trình cho MỘT thiết bị (mock tĩnh).
/// 2 tab: Đếm ngược (Countdown) + Lịch trình (Schedule).
class DeviceTimerScreen extends StatefulWidget {
  final String mac;
  final String deviceName;
  const DeviceTimerScreen({super.key, required this.mac, required this.deviceName});

  @override
  State<DeviceTimerScreen> createState() => _DeviceTimerScreenState();
}

class _DeviceTimerScreenState extends State<DeviceTimerScreen> {
  static const Color tkGreen = Color(0xFF00A651);

  // Mock lịch trình: {time, repeat, action(true=Bật), enabled}
  final List<Map<String, dynamic>> _schedules = [
    {'time': '06:30', 'repeat': 'Hàng ngày', 'on': true, 'enabled': true},
    {'time': '18:00', 'repeat': 'T2 - T6', 'on': true, 'enabled': true},
    {'time': '23:00', 'repeat': 'Hàng ngày', 'on': false, 'enabled': false},
  ];

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hẹn giờ & Lịch trình', style: TextStyle(fontSize: 16)),
            Text(widget.deviceName, style: TextStyle(fontSize: 12, color: textSub, fontWeight: FontWeight.normal)),
          ]),
          backgroundColor: cardColor,
          foregroundColor: textMain,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: tkGreen, labelColor: tkGreen,
            tabs: [Tab(icon: Icon(Icons.timelapse), text: 'Đếm ngược'), Tab(icon: Icon(Icons.event_repeat), text: 'Lịch trình')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: tkGreen, foregroundColor: Colors.white,
          icon: const Icon(Icons.add), label: const Text('Thêm lịch'),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tính năng đang phát triển: Thêm lịch mới'), backgroundColor: tkGreen)),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _buildCountdownTab(cardColor, textMain, textSub),
              _buildScheduleTab(cardColor, textMain, textSub),
            ],
          ),
        ),
      ),
    );
  }

  // TAB ĐẾM NGƯỢC
  Widget _buildCountdownTab(Color cardColor, Color textMain, Color textSub) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 180, height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cardColor, border: Border.all(color: tkGreen.withValues(alpha: 0.4), width: 6)),
              child: Center(child: Text('00:00:00', style: TextStyle(color: textMain, fontSize: 24, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(height: 24),
            Text('Chưa đặt hẹn giờ đếm ngược', style: TextStyle(color: textSub)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Đặt đếm ngược'),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tính năng đang phát triển: Đếm ngược'), backgroundColor: tkGreen)),
            ),
          ],
        ),
      ),
    );
  }

  // TAB LỊCH TRÌNH
  Widget _buildScheduleTab(Color cardColor, Color textMain, Color textSub) {
    if (_schedules.isEmpty) {
      return Center(child: Text('Chưa có lịch trình nào.', style: TextStyle(color: textSub)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _schedules.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final s = _schedules[index];
        final bool on = s['on'] == true;
        return Container(
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(backgroundColor: (on ? tkGreen : Colors.redAccent).withValues(alpha: 0.15), child: Icon(on ? Icons.power_settings_new : Icons.power_off, color: on ? tkGreen : Colors.redAccent)),
            title: Text(s['time'], style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold)),
            subtitle: Text('${s['repeat']} • ${on ? 'Bật thiết bị' : 'Tắt thiết bị'}', style: TextStyle(color: textSub, fontSize: 12)),
            trailing: Switch(
              value: s['enabled'] == true, activeThumbColor: tkGreen,
              onChanged: (v) => setState(() => s['enabled'] = v),
            ),
          ),
        );
      },
    );
  }
}
