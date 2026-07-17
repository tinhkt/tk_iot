import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/home_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/add_member_dialog.dart';
import '../../widgets/app_ui_wrappers.dart';
import '../../localization/app_translations.dart';

/// Màn hình chi tiết sổ thành viên của một nhà — dữ liệu THẬT từ
/// GET /api/homes/{id}/members qua [HomeProvider]. Thêm/gỡ thành viên đều đi qua
/// HomeProvider để members_count trên Home Card (HomeManagementScreen) luôn khớp 100% với
/// danh sách ở đây — cùng một nguồn dữ liệu.
///
/// [NHÚNG, KHÔNG PUSH] Widget này KHÔNG tự Navigator.push và KHÔNG có AppBar riêng — nó được
/// HomeManagementScreen hoán đổi (setState) làm nội dung trong CÙNG vùng Content Area bên
/// phải Sidebar, y hệt cách Dashboard hoán đổi các tab qua _selectedIndex. [onBack] là lối
/// thoát duy nhất, gọi setState phía cha để quay về danh sách Nhà — Sidebar/Header của
/// Dashboard không hề bị che vì không có route mới nào được đẩy lên cả.
class MemberListScreen extends StatefulWidget {
  final Map<String, dynamic> homeData;
  final VoidCallback onBack;
  const MemberListScreen({super.key, required this.homeData, required this.onBack});

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> {
  static const Color _tkGreen = Color(0xFF00A651);
  static const Color _ownerColor = Colors.deepOrange;
  static const Color _adminColor = Colors.blue;

  String? _currentEmail;

  String get _homeId => widget.homeData['home_id'].toString();
  String get _homeName => (widget.homeData['home_name'] ?? _homeId).toString();

  @override
  void initState() {
    super.initState();
    _loadCurrentEmail();
    // Tải sổ thành viên NGAY khi mở màn hình — không chờ tương tác nào khác.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().fetchMembers(_homeId).catchError((e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.redAccent),
        );
      });
    });
  }

  /// Email người đang đăng nhập, giải mã trực tiếp từ JWT (cùng cách dashboard_screen.dart
  /// đang làm) — dùng để loại chính mình khỏi nút "Xóa khỏi nhà" (không ai tự gỡ mình).
  Future<void> _loadCurrentEmail() async {
    final token = await AuthService().getToken();
    if (token == null) return;
    final parts = token.split('.');
    if (parts.length != 3) return;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (mounted) setState(() => _currentEmail = payload['email'] as String?);
    } catch (_) {
      // token hỏng/không giải mã được -> giữ null, coi như "không loại ai" (an toàn hơn crash)
    }
  }

  void _showAddMemberDialog() async {
    // Gọi từ ElevatedButton.onPressed (tap handler) -> listen: false, tránh "liệt nút"
    // (context.watch() ngoài pha build thật — xem app_translations.dart).
    final t = AppTranslations.of(context, listen: false);
    final provider = context.read<HomeProvider>();
    // [GLASS THEME] AddMemberDialog tự trả về nội dung thô (không còn tự bọc Dialog/
    // GlassCard trong build() của nó) nên đưa thẳng vào child: của showAppDialog.
    final result = await showAppDialog<bool>(
      context: context,
      child: AddMemberDialog(
        onSubmit: (email, role) => provider.addMember(_homeId, email, role),
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.text('add_member_success')), backgroundColor: _tkGreen),
      );
    }
  }

  Future<void> _confirmAndRemove(HomeMember member) async {
    // Gọi từ PopupMenuButton.onSelected (tap handler) -> listen: false.
    final t = AppTranslations.of(context, listen: false);
    // [GLASS THEME] AlertDialog (title/content/actions) ĐÃ THAY bằng showAppDialog().
    final confirm = await showAppDialog<bool>(
          context: context,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.text('confirm_delete_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                // [GIỮ NGUYÊN BIẾN ĐỘNG] member.email — chỉ câu văn quanh dịch.
                Text('${t.text('confirm_remove_member_prefix')}${member.email}${t.text('confirm_remove_member_suffix')}'),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.text('cancel'))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t.text('delete'), style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!confirm || !mounted) return;

    // [BẮT LỖI THÉP] try-catch tuyệt đối — mọi HTTP Exception (403/404/409...) đều phải
    // ra tới đây, KHÔNG có nhánh nào được phép nuốt câm im lặng.
    try {
      await context.read<HomeProvider>().removeMember(_homeId, member.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        // [GIỮ NGUYÊN BIẾN ĐỘNG] member.email — chỉ câu văn quanh dịch.
        SnackBar(content: Text('${t.text('removed_member_prefix')}${member.email}${t.text('removed_member_suffix')}'), backgroundColor: _tkGreen),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final t = AppTranslations.of(context);
    final provider = context.watch<HomeProvider>();
    final members = provider.membersOf(_homeId);
    final isLoading = provider.isLoadingMembers(_homeId);

    final owners = members.where((m) => m.role == 'OWNER').toList();
    final admins = members.where((m) => m.role == 'ADMIN').toList();
    final users = members.where((m) => m.role != 'OWNER' && m.role != 'ADMIN').toList();

    return AppScaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBreadcrumb(textMain, textSub, t),
              const SizedBox(height: 20),
              _buildHeader(textMain, textSub, t),
              const SizedBox(height: 28),
              Expanded(
                child: isLoading && members.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: _tkGreen))
                    : RefreshIndicator(
                        color: _tkGreen,
                        onRefresh: () => context.read<HomeProvider>().fetchMembers(_homeId),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            _buildOwnerSection(owners, textMain, textSub, isDark, t),
                            const SizedBox(height: 24),
                            _buildRoleSection(
                              title: t.text('admin_role_title'),
                              icon: Icons.shield_rounded,
                              accent: _adminColor,
                              list: admins,
                              textMain: textMain,
                              textSub: textSub,
                              isDark: isDark,
                              emptyText: t.text('no_admins_yet'),
                              t: t,
                            ),
                            const SizedBox(height: 24),
                            _buildRoleSection(
                              title: t.text('members'),
                              icon: Icons.people_alt_rounded,
                              accent: _tkGreen,
                              list: users,
                              textMain: textMain,
                              textSub: textSub,
                              isDark: isDark,
                              emptyText: t.text('no_members_yet'),
                              t: t,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // BREADCRUMB — thay cho AppBar + nút Back to tướng: "Quản lý Nhà › Thành viên"
  // ==========================================================================
  Widget _buildBreadcrumb(Color textMain, Color textSub, AppTranslations t) {
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onBack,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 18, color: textSub),
                  const SizedBox(width: 6),
                  Text(t.text('home_management'), style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 16, color: textSub.withValues(alpha: 0.6)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(t.text('members'), style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildHeader(Color textMain, Color textSub, AppTranslations t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.text('members'), style: TextStyle(color: textMain, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              // [GIỮ NGUYÊN BIẾN ĐỘNG] _homeName — tên nhà do người dùng đặt, không dịch.
              Text(_homeName, style: TextStyle(color: textSub, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _tkGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
          label: Text(t.text('add_member'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          onPressed: _showAddMemberDialog,
        ),
      ],
    );
  }

  // ==========================================================================
  // KHU VỰC 1 — CHỦ NHÀ: đóng khung nổi bật riêng, luôn trên cùng, KHÔNG có nút xóa.
  // ==========================================================================
  Widget _buildOwnerSection(List<HomeMember> owners, Color textMain, Color textSub, bool isDark, AppTranslations t) {
    if (owners.isEmpty) {
      // Không lẽ xảy ra (Backend luôn ghép owner vào danh sách) — vẫn thủ thân, không crash.
      return _sectionHeader(t.text('home_owner'), Icons.workspace_premium_rounded, _ownerColor, 0, textSub);
    }
    final owner = owners.first;
    final bool isSelf = _currentEmail != null && owner.email == _currentEmail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(t.text('home_owner'), Icons.workspace_premium_rounded, _ownerColor, 1, textSub),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _ownerColor.withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _ownerColor.withValues(alpha: 0.4), width: 1.4),
            boxShadow: [if (!isDark) BoxShadow(color: _ownerColor.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 24, backgroundColor: _ownerColor.withValues(alpha: 0.2), child: const Icon(Icons.workspace_premium_rounded, color: _ownerColor)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // [GIỮ NGUYÊN BIẾN ĐỘNG] owner.email — chỉ hậu tố "(Bạn)" dịch.
                      '${owner.email}${isSelf ? ' ${t.text('you_suffix')}' : ''}',
                      style: TextStyle(color: textMain, fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(t.text('home_owner_desc'), style: TextStyle(color: textSub, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _roleBadge('OWNER', t),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // KHU VỰC 2 & 3 — QUẢN TRỊ VIÊN / THÀNH VIÊN: Card kính mờ bo góc, danh sách ListTile.
  // ==========================================================================
  Widget _buildRoleSection({
    required String title,
    required IconData icon,
    required Color accent,
    required List<HomeMember> list,
    required Color textMain,
    required Color textSub,
    required bool isDark,
    required String emptyText,
    required AppTranslations t,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title, icon, accent, list.length, textSub),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(child: Text(emptyText, style: TextStyle(color: textSub, fontSize: 13))),
          )
        else
          AppContainer(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(18),
            child: Column(
              children: [
                for (int i = 0; i < list.length; i++) ...[
                  _buildMemberTile(list[i], textMain, textSub, t),
                  if (i != list.length - 1) Divider(height: 1, indent: 68, color: isDark ? Colors.white10 : Colors.grey.shade200),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color accent, int count, Color textSub) {
    return Row(
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 8),
        Text(title.toUpperCase(), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildMemberTile(HomeMember mem, Color textMain, Color textSub, AppTranslations t) {
    final bool isSelf = _currentEmail != null && mem.email == _currentEmail;
    final bool canRemove = mem.role != 'OWNER' && !isSelf;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(backgroundColor: _tkGreen.withValues(alpha: 0.15), child: const Icon(Icons.person_rounded, color: _tkGreen)),
      title: Text(
        // [GIỮ NGUYÊN BIẾN ĐỘNG] mem.email — chỉ hậu tố "(Bạn)" dịch.
        '${mem.email}${isSelf ? ' ${t.text('you_suffix')}' : ''}',
        style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _roleBadge(mem.role, t),
          const SizedBox(width: 4),
          if (canRemove)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: textSub, size: 20),
              onSelected: (val) {
                if (val == 'remove') _confirmAndRemove(mem);
              },
              // itemBuilder của PopupMenuButton chạy TỪ tap handler, KHÔNG phải build pass thật
              // -> KHÔNG gọi AppTranslations.of() ở đây; dùng lại `t` đã lấy an toàn từ build()
              // (chỉ là 1 giá trị thuần, không truy cập lại context).
              itemBuilder: (_) => [
                PopupMenuItem(value: 'remove', child: Text(t.text('remove_from_home_menu'), style: const TextStyle(color: Colors.red))),
              ],
            )
          else
            const SizedBox(width: 40), // giữ căn lề đều với các dòng có nút 3 chấm
        ],
      ),
    );
  }

  /// Badge màu theo vai trò — OWNER cam/đỏ, ADMIN xanh dương, USER xanh lá nhạt (đồng bộ
  /// màu thương hiệu _tkGreen thay vì xám trung tính để nhất quán với toàn app).
  Widget _roleBadge(String role, AppTranslations t) {
    late final Color color;
    late final String label;
    switch (role) {
      case 'OWNER':
        color = _ownerColor;
        label = t.text('home_owner').toUpperCase();
        break;
      case 'ADMIN':
        color = _adminColor;
        label = t.text('admin_badge');
        break;
      default:
        color = _tkGreen;
        label = t.text('member_role').toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
    );
  }
}
