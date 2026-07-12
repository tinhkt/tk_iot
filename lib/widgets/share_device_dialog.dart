import 'dart:ui'; // BackdropFilter / ImageFilter.blur (kính mờ)
import 'package:flutter/material.dart';

const Color _tkGreen = Color(0xFF00A651);

/// showShareDeviceDialog — Dialog kính mờ chia sẻ thiết bị (mock): QR giả lập + nhập Email/SĐT.
Future<void> showShareDeviceDialog(BuildContext context, {required String mac, required String deviceName}) {
  final TextEditingController inviteCtrl = TextEditingController();

  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    builder: (ctx) {
      final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
      final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
      final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 360,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(ctx).scaffoldBackgroundColor.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.share, color: _tkGreen),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Chia sẻ thiết bị', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold))),
                    IconButton(icon: Icon(Icons.close, color: textSub), onPressed: () => Navigator.pop(ctx)),
                  ]),
                  const SizedBox(height: 4),
                  Text(deviceName, style: TextStyle(color: textSub, fontSize: 13)),
                  const SizedBox(height: 20),

                  // Khối QR giả lập
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.qr_code_2, size: 150, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(child: Text('Quét mã để nhận quyền điều khiển', style: TextStyle(color: textSub, fontSize: 12))),
                  const SizedBox(height: 20),

                  Text('Hoặc mời qua Email / SĐT:', style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: inviteCtrl,
                    style: TextStyle(color: textMain),
                    decoration: InputDecoration(
                      hintText: 'vd: ban@gmail.com hoặc 09xxxxxxxx',
                      hintStyle: TextStyle(color: textSub),
                      prefixIcon: Icon(Icons.person_add_alt, color: textSub),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Gửi lời mời'),
                      onPressed: () {
                        final target = inviteCtrl.text.trim();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(target.isEmpty ? 'Tính năng đang phát triển: Chia sẻ thiết bị' : 'Đã gửi lời mời tới $target'),
                          backgroundColor: _tkGreen,
                        ));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
