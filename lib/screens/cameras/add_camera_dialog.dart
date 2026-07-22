import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../../models/camera_model.dart';
import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';

/// [QUÉT LAN ONVIF] Popup danh sách camera tìm được — trả về [DiscoveredCameraModel] người dùng
/// chọn (null nếu hủy/đóng không chọn gì). Tách hàm riêng để build() chính không phình quá dài.
Future<DiscoveredCameraModel?> _showDiscoveredCamerasPicker(BuildContext context, List<DiscoveredCameraModel> cameras) {
  return showAppDialog<DiscoveredCameraModel>(
    context: context,
    maxWidth: 440,
    child: Builder(builder: (context) {
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
      final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.wifi_find_rounded, color: _tkGreen, size: 22),
              const SizedBox(width: 8),
              Text('Đã tìm thấy ${cameras.length} camera', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: cameras.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                itemBuilder: (context, index) {
                  final cam = cameras[index];
                  final String subtitle = [
                    cam.ipAddress,
                    if (cam.macAddress.isNotEmpty) cam.macAddress,
                    if (cam.model.isNotEmpty) cam.model,
                    if (cam.serialNumber.isNotEmpty) 'SN: ${cam.serialNumber}',
                  ].join(' • ');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.videocam_rounded, color: Colors.blueAccent),
                    title: Text(cam.name.isNotEmpty ? cam.name : cam.ipAddress, style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                    subtitle: Text(subtitle, style: TextStyle(color: textSub, fontSize: 12), overflow: TextOverflow.ellipsis),
                    trailing: Icon(Icons.chevron_right, color: textSub),
                    onTap: () => Navigator.of(context).pop(cam),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Đóng')),
            ),
          ],
        ),
      );
    }),
  );
}

const Color _tkGreen = Color(0xFF00A651);

/// [CAMERA IP — THÊM MỚI] Preset Stream Path cho các hãng camera IP phổ biến tại VN — điền
/// sẵn để người dùng không cần tra cứu tài liệu hãng, vẫn sửa tay được nếu camera khác model.
/// Giá trị RỖNG = "Tuỳ chỉnh" (người dùng tự gõ).
const Map<String, String> _streamPathPresets = {
  'Tuỳ chỉnh': '',
  'Hikvision (luồng chính)': '/Streaming/Channels/101',
  'Hikvision (luồng phụ)': '/Streaming/Channels/102',
  'Dahua / Imou (luồng chính)': '/cam/realmonitor?channel=1&subtype=0',
  'Dahua / Imou (luồng phụ)': '/cam/realmonitor?channel=1&subtype=1',
  'ONVIF chung': '/onvif1',
};

/// showAddCameraDialog — mở popup Thêm Camera, trả về [CameraModel] vừa tạo nếu lưu thành
/// công (null nếu người dùng hủy) để nơi gọi tự cập nhật danh sách mà không cần fetch lại.
Future<CameraModel?> showAddCameraDialog(BuildContext context, {required String homeId}) {
  return showAppDialog<CameraModel>(
    context: context,
    maxWidth: 440,
    child: _AddCameraDialogBody(homeId: homeId),
  );
}

class _AddCameraDialogBody extends StatefulWidget {
  final String homeId;
  const _AddCameraDialogBody({required this.homeId});

  @override
  State<_AddCameraDialogBody> createState() => _AddCameraDialogBodyState();
}

class _AddCameraDialogBodyState extends State<_AddCameraDialogBody> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '554');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _streamPathController = TextEditingController();
  final _subStreamPathController = TextEditingController();

  String _selectedPreset = 'Tuỳ chỉnh';
  String _selectedSubPreset = 'Tuỳ chỉnh';
  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _isScanning = false;
  // null = chưa test lần nào; true/false = kết quả lần test GẦN NHẤT — đổi bất kỳ trường nào
  // liên quan kết nối (IP/Port) sẽ tự reset về null (xem _onConnectionFieldChanged) để không
  // hiện "Đã kết nối được" LỖI THỜI cho một IP/Port đã bị sửa sau đó.
  bool? _testResult;

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _streamPathController.dispose();
    _subStreamPathController.dispose();
    super.dispose();
  }

  void _onConnectionFieldChanged() {
    if (_testResult != null) setState(() => _testResult = null);
  }

  // [TEST CONNECTION] Chỉ kiểm tra CỔNG TCP có mở/phản hồi được không (bắt tay RTSP thật cần
  // 1 thư viện RTSP client riêng, ngoài phạm vi 1 nút kiểm tra nhanh trước khi lưu) — đủ để
  // phát hiện SAI IP/PORT hoàn toàn hoặc camera không cùng mạng LAN, KHÔNG đảm bảo user/mật
  // khẩu đúng (chỉ RTSP handshake thật mới biết được điều đó).
  Future<void> _testConnection() async {
    final String ip = _ipController.text.trim();
    final int port = int.tryParse(_portController.text.trim()) ?? 554;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nhập địa chỉ IP trước khi kiểm tra kết nối')));
      return;
    }
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
      socket.destroy();
      if (mounted) setState(() => _testResult = true);
    } catch (_) {
      if (mounted) setState(() => _testResult = false);
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  // [QUÉT LAN ONVIF] Backend quét NGAY TRÊN mạng LAN của chính Server (WS-Discovery, xem
  // internal/onvif/discovery.go) — chỉ tìm thấy camera hỗ trợ ONVIF, KHÔNG thay thế hoàn toàn
  // nhập tay (camera RTSP-only không ONVIF, hoặc Server/camera khác LAN, vẫn phải nhập tay —
  // đúng yêu cầu "vẫn giữ tuỳ chọn nhập thủ công").
  Future<void> _scanLan() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    final result = await ApiService().discoverCameras();
    if (!mounted) return;
    setState(() => _isScanning = false);

    if (result.cameras == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'Quét mạng LAN thất bại'), backgroundColor: Colors.redAccent));
      return;
    }
    if (result.cameras!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không tìm thấy camera ONVIF nào trong mạng LAN của Server')));
      return;
    }

    final picked = await _showDiscoveredCamerasPicker(context, result.cameras!);
    if (picked == null || !mounted) return;
    setState(() {
      _ipController.text = picked.ipAddress;
      // Model/Serial (nếu có) đính kèm vào Tên để không mất thông tin — form Thêm Camera không
      // có ô Serial Number riêng (camera RTSP không lưu SN, khác hẳn khuôn dữ liệu Camera Imou).
      _nameController.text = picked.name.isNotEmpty ? picked.name : picked.ipAddress;
      _onConnectionFieldChanged();
    });
    if (picked.serialNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã điền IP/Tên — camera này không trả Serial Number qua ONVIF (có thể cần xác thực), hãy kiểm tra tem/nhãn camera nếu cần')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final result = await ApiService().addCamera(
      homeId: widget.homeId,
      name: _nameController.text.trim(),
      ipAddress: _ipController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 554,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      streamPath: _streamPathController.text.trim(),
      subStreamPath: _subStreamPathController.text.trim(),
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
                const Icon(Icons.videocam_rounded, color: Colors.blueAccent, size: 22),
                const SizedBox(width: 8),
                Text('Thêm Camera IP', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              Text(
                'Camera phải cùng mạng LAN với thiết bị đang mở App để xem được luồng RTSP trực tiếp.',
                style: TextStyle(color: textSub, fontSize: 12),
              ),
              const SizedBox(height: 16),
              // [QUÉT LAN ONVIF] Quét trước để tự điền IP/Tên — vẫn có thể sửa tay mọi trường bên
              // dưới sau khi chọn, hoặc bỏ qua nút này và nhập thủ công như trước đây.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isScanning ? null : _scanLan,
                  icon: _isScanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_find_rounded),
                  label: Text(_isScanning ? 'Đang quét mạng LAN...' : 'Quét mạng LAN (ONVIF)'),
                  style: OutlinedButton.styleFrom(foregroundColor: _tkGreen, side: const BorderSide(color: _tkGreen), padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Chỉ tìm được camera hỗ trợ ONVIF cùng mạng LAN với Server. Không thấy camera? Nhập thủ công bên dưới.',
                style: TextStyle(color: textSub, fontSize: 11),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
              const SizedBox(height: 16),
              AppTextField(
                controller: _nameController,
                labelText: 'Tên Camera',
                hintText: 'Vd: Camera cổng chính',
                prefixIcon: const Icon(Icons.label_outline_rounded),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên camera' : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: AppTextField(
                      controller: _ipController,
                      labelText: 'Địa chỉ IP',
                      hintText: 'Vd: 192.168.1.108',
                      prefixIcon: const Icon(Icons.lan_outlined),
                      keyboardType: TextInputType.text,
                      onChanged: (_) => _onConnectionFieldChanged(),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập IP' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: AppTextField(
                      controller: _portController,
                      labelText: 'Port',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _onConnectionFieldChanged(),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n <= 0 || n > 65535) return 'Port không hợp lệ';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _usernameController,
                labelText: 'Tên đăng nhập (nếu có)',
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _passwordController,
                labelText: 'Mật khẩu (nếu có)',
                obscureText: _obscurePassword,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 12),
              AppDropdown<String>(
                value: _selectedPreset,
                labelText: 'Mẫu Stream Path (hãng camera)',
                prefixIcon: const Icon(Icons.tune_rounded),
                items: [for (final k in _streamPathPresets.keys) DropdownMenuItem(value: k, child: Text(k, overflow: TextOverflow.ellipsis))],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedPreset = v;
                    if (_streamPathPresets[v]!.isNotEmpty) _streamPathController.text = _streamPathPresets[v]!;
                  });
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _streamPathController,
                labelText: 'Stream Path (luồng chính — dùng khi Phóng to)',
                hintText: '/Streaming/Channels/101',
                prefixIcon: const Icon(Icons.route_outlined),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
              const SizedBox(height: 12),
              // [HIỆU NĂNG UX — PHẦN 3] Luồng PHỤ RIÊNG cho khung xem trước Dashboard — nhẹ hơn
              // nhiều so với phát thẳng luồng chính trong 1 ô nhỏ khi cuộn màn hình. Để trống =
              // App tự rơi về luồng chính (vẫn xem được, chỉ nặng hơn), KHÔNG bắt buộc.
              Row(children: [
                Icon(Icons.speed_rounded, size: 16, color: textSub),
                const SizedBox(width: 6),
                Expanded(child: Text('Luồng phụ cho khung xem trước (khuyến nghị — nhẹ hơn nhiều)', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 8),
              AppDropdown<String>(
                value: _selectedSubPreset,
                labelText: 'Mẫu Stream Path luồng phụ',
                prefixIcon: const Icon(Icons.tune_rounded),
                items: [for (final k in _streamPathPresets.keys) DropdownMenuItem(value: k, child: Text(k, overflow: TextOverflow.ellipsis))],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedSubPreset = v;
                    _subStreamPathController.text = _streamPathPresets[v]!;
                  });
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _subStreamPathController,
                labelText: 'Stream Path (luồng phụ — để trống nếu không có)',
                hintText: '/Streaming/Channels/102',
                prefixIcon: const Icon(Icons.route_outlined),
              ),
              const SizedBox(height: 16),

              // [TEST CONNECTION] Chỉ kiểm tra cổng TCP mở được không — xem giải thích ở _testConnection().
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(_testResult == null ? Icons.wifi_tethering_rounded : (_testResult! ? Icons.check_circle_rounded : Icons.error_rounded),
                            color: _testResult == null ? null : (_testResult! ? _tkGreen : Colors.redAccent)),
                    label: Text(_isTesting
                        ? 'Đang kiểm tra...'
                        : _testResult == null
                            ? 'Kiểm tra kết nối'
                            : (_testResult! ? 'Kết nối được cổng TCP' : 'Không kết nối được')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _testResult == null ? textMain : (_testResult! ? _tkGreen : Colors.redAccent),
                      side: BorderSide(color: _testResult == null ? (isDark ? Colors.white24 : Colors.black26) : (_testResult! ? _tkGreen : Colors.redAccent)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                'Chỉ kiểm tra camera có phản hồi đúng địa chỉ/cổng không — không xác nhận tài khoản/mật khẩu (cần thử phát thử mới biết chắc).',
                style: TextStyle(color: textSub, fontSize: 11),
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
                        : const Text('Lưu Camera'),
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
