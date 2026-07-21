import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/imou_camera_model.dart';
import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';

const Color _tkGreen = Color(0xFF00A651);

/// showAddImouCameraDialog — mở popup Thêm Camera P2P (Imou), trả về [ImouCameraModel] vừa tạo
/// nếu lưu thành công (null nếu hủy). KHÁC showAddCameraDialog (RTSP) — không cần IP/Port/Stream
/// Path, chỉ cần Device Serial (DN) + mã xác thực in trên nhãn camera thật, vì camera P2P đi qua
/// Cloud của hãng chứ không kết nối thẳng qua LAN.
Future<ImouCameraModel?> showAddImouCameraDialog(BuildContext context, {required String homeId}) {
  return showAppDialog<ImouCameraModel>(
    context: context,
    maxWidth: 440,
    child: _AddImouCameraDialogBody(homeId: homeId),
  );
}

class _AddImouCameraDialogBody extends StatefulWidget {
  final String homeId;
  const _AddImouCameraDialogBody({required this.homeId});

  @override
  State<_AddImouCameraDialogBody> createState() => _AddImouCameraDialogBodyState();
}

class _AddImouCameraDialogBodyState extends State<_AddImouCameraDialogBody> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serialController = TextEditingController();
  final _verifyCodeController = TextEditingController();

  final MobileScannerController _scannerController = MobileScannerController();
  bool _scanning = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _serialController.dispose();
    _verifyCodeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  // --- XIN QUYỀN CAMERA — CÙNG TRÌNH TỰ ĐÃ DÙNG Ở add_device_dialog.dart ---
  // Desktop bỏ qua (permission_handler chỉ quản Android/iOS). Không xin quyền trước khi mở
  // MobileScanner là nguyên nhân iOS kill app ngay khi chạm camera nếu thiếu bước hỏi tường minh.
  Future<bool> _ensureCameraPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    status = await Permission.camera.request();
    if (status.isGranted) return true;
    if (!mounted) return false;

    if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Quyền Camera đã bị chặn — mở Cài đặt để cấp lại'),
        backgroundColor: Colors.orange,
        action: SnackBarAction(label: 'Mở Cài đặt', textColor: Colors.white, onPressed: openAppSettings),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cần quyền Camera để quét mã QR'), backgroundColor: Colors.redAccent));
    }
    return false;
  }

  Future<void> _toggleScanner() async {
    if (_scanning) {
      setState(() => _scanning = false);
      return;
    }
    if (!await _ensureCameraPermission()) return;
    if (mounted) setState(() => _scanning = true);
  }

  // [ĐỊNH DẠNG QR CHƯA XÁC NHẬN] Mã QR in trên nhãn camera Imou thật thường CHỨA Device Serial
  // (có thể kèm thêm thông tin khác tùy model) — chưa có camera thật để xác nhận định dạng chính
  // xác, nên tạm coi TOÀN BỘ nội dung quét được là Device Serial, đổ thẳng vào ô nhập để người
  // dùng TỰ KIỂM TRA/sửa lại trước khi lưu, KHÔNG tự động lưu ngay khi quét được.
  void _onQrDetected(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) return;
    setState(() {
      _serialController.text = barcodes.first.rawValue!;
      _scanning = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final result = await ApiService().addImouCamera(
      homeId: widget.homeId,
      name: _nameController.text.trim(),
      deviceSerial: _serialController.text.trim(),
      verifyCode: _verifyCodeController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.camera != null) {
      Navigator.of(context).pop(result.camera);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'Lỗi không xác định'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.cloud_queue_rounded, color: Colors.blueAccent, size: 22),
                const SizedBox(width: 8),
                Text('Thêm Camera Imou (P2P)', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              Text(
                'Xem được qua Internet, không cần cùng mạng LAN — camera phải là camera Imou thật đã ghép Wi-Fi bằng App Imou trước.',
                style: TextStyle(color: textSub, fontSize: 12),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _nameController,
                labelText: 'Tên Camera',
                hintText: 'Vd: Camera ngoài trời',
                prefixIcon: const Icon(Icons.label_outline_rounded),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên camera' : null,
              ),
              const SizedBox(height: 12),
              if (_scanning)
                SizedBox(
                  height: 260,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        MobileScanner(controller: _scannerController, onDetect: _onQrDetected),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                            onPressed: () => setState(() => _scanning = false),
                            style: IconButton.styleFrom(backgroundColor: Colors.black45),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _toggleScanner,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Quét mã QR trên nhãn camera'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _serialController,
                labelText: 'Device Serial (DN)',
                hintText: 'Quét QR ở trên hoặc nhập tay',
                prefixIcon: const Icon(Icons.qr_code_rounded),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập hoặc quét Device Serial' : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _verifyCodeController,
                labelText: 'Mã xác thực (Verify Code)',
                hintText: 'In trên nhãn camera, thường 6-9 ký tự',
                prefixIcon: const Icon(Icons.pin_outlined),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập mã xác thực' : null,
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Hủy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Gắn Camera'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
