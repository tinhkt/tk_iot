import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';

// ============================================================================
// 🪟 APP UI WRAPPERS — KIẾN TRÚC THEME "NGÃ RẼ" (GLASS vs MẶC ĐỊNH)
// ============================================================================
// NGUYÊN TẮC THÉP: đây là file DUY NHẤT quyết định "kính hay không kính". Mọi widget
// trong file này tự đọc `context.watch<ThemeProvider>().isGlassThemeEnabled` và rẽ nhánh:
//   - false -> trả về ĐÚNG những gì màn hình đang vẽ hôm nay (Material/Card phẳng quen
//     thuộc) — không đổi 1 pixel nào so với trước khi có file này.
//   - true  -> trả về phiên bản Ultra-Glassmorphism (frost blur + viền hắt sáng gradient +
//     bóng chữ) theo đúng specs Phần 2.
// KHÔNG file màn hình nào khác được tự vẽ hiệu ứng kính riêng — mọi chỗ cần "thẻ"/"khung"/
// "popup" đều gọi qua đây để đổi theme là đổi TOÀN APP một chỗ.
//
// [HIỆU NĂNG — PHẦN 4] Quy tắc bắt buộc khi thêm widget mới vào file này:
//   1. MỌI mặt kính (có BackdropFilter) phải nằm trong _GlassSurface — nơi DUY NHẤT gọi
//      BackdropFilter trong toàn bộ file, và đã tự bọc RepaintBoundary + ClipRRect quanh nó.
//      Không gọi BackdropFilter ở bất kỳ đâu khác trong file này hay ngoài app.
//   2. TUYỆT ĐỐI không lồng 2 _GlassSurface trực tiếp vào nhau (surface cha chứa surface con
//      ngay sát vách) — mỗi lớp blur là một lần GPU phải render lại toàn bộ khung hình phía
//      sau nó; lồng 2 lớp = tăng gấp đôi chi phí cho VÙNG CHỒNG LẤN mà mắt gần như không
//      phân biệt được với 1 lớp. Nếu cần "thẻ trong thẻ", thẻ con dùng nền phẳng
//      (Colors.white.withValues(alpha: 0.06), KHÔNG BackdropFilter riêng).
//   3. Nền Aurora (_AuroraMeshBackground) KHÔNG dùng BackdropFilter — chỉ là các khối
//      RadialGradient tĩnh xếp lớp trong Stack (rẻ, vẽ 1 lần, không đụng GPU blur pass) —
//      đây là "nền đa sắc" bắt buộc phải có phía sau để BackdropFilter của các thẻ có gì để
//      hút màu; nếu nền chỉ là 1 màu phẳng, hiệu ứng kính sẽ vô nghĩa (nhìn như kính mờ xám).

// ============================================================================
// 🎨 HẰNG SỐ QUANG HỌC DÙNG CHUNG (Phần 2 — Optical Specs)
// ============================================================================
const double kGlassBlurSigma = 20.0;
final Color kGlassFrostFill = Colors.white.withValues(alpha: 0.05);
const double kGlassBorderWidth = 1.3;

/// [Tương phản] Bóng đổ mờ cho MỌI chữ nằm trên kính — đảm bảo đọc được bất chấp màu Aurora
/// phía sau. Text thường KẾ THỪA qua DefaultTextStyle (mọi widget kính trong file này tự
/// merge sẵn) — chỉ cần gọi thẳng nếu bạn tự dựng Text() nằm ngoài các wrapper dưới đây.
const List<Shadow> kGlassTextShadow = [Shadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 1))];

/// Icon KHÔNG kế thừa DefaultTextStyle (khác Text) — Flutter không có IconTheme cấp bóng đổ,
/// nên phải truyền tay `shadows: kGlassIconShadow` vào từng Icon() nằm trên kính, hoặc dùng
/// [AppIcon] bên dưới (đã gắn sẵn).
const List<Shadow> kGlassIconShadow = kGlassTextShadow;

/// Đọc nhanh cờ Glass Theme — dùng trong build() của MỌI widget dưới đây thay vì gọi
/// Provider.of lặp lại. `listen:true` (qua context.watch) để widget tự vẽ lại khi người
/// dùng bật/tắt công tắc trong Cài đặt.
bool _isGlass(BuildContext context) => context.watch<ThemeProvider>().isGlassThemeEnabled;

// ============================================================================
// 🌌 NỀN AURORA / MESH GRADIENT (Phần 2 — Global Background)
// ============================================================================
/// Các dải màu pastel hòa quyện, TĨNH (không AnimationController) — vẽ 1 lần, không tốn
/// khung hình nào sau đó. Nếu sau này muốn "chuyển động nhẹ", chỉ nên animate Ở ĐÂY (KHÔNG
/// BAO GIỜ animate bên trong _GlassSurface — mỗi khung hình đổi sẽ ép toàn bộ card kính
/// phía trên blur lại, sập FPS ngay).
class _AuroraMeshBackground extends StatelessWidget {
  const _AuroraMeshBackground();

  static const _blobsDark = [
    (Color(0xFF6D28D9), Alignment(-0.9, -0.8), 420.0), // tím
    (Color(0xFF0EA5E9), Alignment(0.9, -0.6), 460.0),  // xanh dương
    (Color(0xFF00A651), Alignment(-0.6, 0.9), 400.0),  // xanh lá thương hiệu
    (Color(0xFFDB2777), Alignment(0.8, 0.8), 380.0),   // hồng
  ];
  static const _blobsLight = [
    (Color(0xFFA78BFA), Alignment(-0.9, -0.8), 420.0),
    (Color(0xFF7DD3FC), Alignment(0.9, -0.6), 460.0),
    (Color(0xFF6EE7B7), Alignment(-0.6, 0.9), 400.0),
    (Color(0xFFF9A8D4), Alignment(0.8, 0.8), 380.0),
  ];

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final blobs = isDark ? _blobsDark : _blobsLight;
    return RepaintBoundary(
      child: Container(
        color: isDark ? const Color(0xFF0B1120) : const Color(0xFFEFF3F8),
        child: Stack(
          children: [
            for (final (color, align, size) in blobs)
              Align(
                alignment: align,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [color.withValues(alpha: isDark ? 0.55 : 0.65), color.withValues(alpha: 0.0)],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 🖌️ VIỀN HẮT SÁNG 3D (Phần 2 — Glossy Highlight)
// ============================================================================
/// Flutter không có BorderSide gradient sẵn — vẽ tay bằng CustomPaint (không cần thư viện
/// ngoài). [inverted]=true đảo hướng sáng (dùng cho ô nhập liệu "chìm" — xem AppTextField).
class _GlassBorderPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final bool inverted;
  const _GlassBorderPainter({required this.borderRadius, this.inverted = false});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(kGlassBorderWidth / 2);
    final rrect = borderRadius.toRRect(inset);
    final begin = inverted ? Alignment.bottomRight : Alignment.topLeft;
    final end = inverted ? Alignment.topLeft : Alignment.bottomRight;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kGlassBorderWidth
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: [Colors.white.withValues(alpha: 0.5), Colors.white.withValues(alpha: 0.05)],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassBorderPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius || oldDelegate.inverted != inverted;
}

// ============================================================================
// 🧊 LÕI KÍNH DÙNG CHUNG (Phần 2 — Frost & Blur) — DUY NHẤT nơi gọi BackdropFilter
// ============================================================================
class _GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? width, height;
  final bool inverted; // true = "chìm" (form nhập liệu), false = "nổi" (thẻ)
  final Color? tint; // overlay màu thêm lên lớp frost (vd trạng thái lỗi/thành công)
  // [ĐỢT 9] Ghi đè TOÀN BỘ màu frost, KHÔNG qua công thức blend nhẹ (12%) của [tint] — dùng
  // khi cần độ đục cao hơn hẳn mức mặc định để đảm bảo tương phản chữ (vd Popup Avatar trên
  // nền Sáng Kính, xem _buildUserAvatarMenu trong dashboard_screen.dart).
  final Color? frostOverride;

  const _GlassSurface({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.padding,
    this.width,
    this.height,
    this.inverted = false,
    this.tint,
    this.frostOverride,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedRadius = borderRadius.resolve(Directionality.of(context));
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [ĐỢT 9 — ĐÁNH NỔI KHỐI] Viền + đổ bóng "nổi" CHỈ áp cho mặt kính NỔI (thẻ/dialog/sheet,
    // inverted=false) — mặt kính CHÌM (form nhập liệu, inverted=true) giữ nguyên nhìn "khoét
    // vào" như thiết kế gốc, không hợp với hiệu ứng nổi khối này.
    final BoxDecoration outerDecoration = inverted
        ? BoxDecoration(borderRadius: borderRadius)
        : BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15),
            ],
          );

    // [PHẦN 4 — HIỆU NĂNG] RepaintBoundary CÔ LẬP vùng kính: nội dung bên trong (nhiệt độ,
    // % quạt...) đổi liên tục sẽ chỉ vẽ lại ĐÚNG khung hình chữ nhật này, không ép cả cây
    // widget cha (Dashboard/List) vẽ lại theo — đây là chốt chặn overdraw bắt buộc.
    //
    // [ĐỢT 9 — SHADOW PHẢI Ở NGOÀI CLIP] outerDecoration (viền + đổ bóng) BẮT BUỘC nằm ở
    // Container NGOÀI CÙNG, TRƯỚC ClipRRect — boxShadow tràn ra ngoài biên bo góc, nếu đặt
    // trong Container bị ClipRRect/BackdropFilter cắt (như Container frost bên dưới) thì
    // bóng đổ sẽ bị cắt mất hoàn toàn, không hiện ra được.
    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        decoration: outerDecoration,
        child: ClipRRect(
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: kGlassBlurSigma, sigmaY: kGlassBlurSigma),
            child: Container(
              // [FIX — Viền kính lệch vào trong] `padding` KHÔNG đặt ở đây nữa — Container.padding
              // sẽ kéo TOÀN BỘ child (kể cả Positioned.fill border bên dưới) vào trong, khiến viền
              // hắt sáng vẽ ngay sát mép chữ/icon thay vì tại rìa ngoài thật của thẻ (nơi nền frost/
              // decoration dưới đây vẫn phủ tới). `padding` giờ chỉ áp cho riêng nội dung `child`
              // qua Padding tường minh trong Stack, TÁCH RIÊNG khỏi border.
              decoration: BoxDecoration(
                color: frostOverride ?? (tint != null ? Color.alphaBlend(tint!.withValues(alpha: 0.12), kGlassFrostFill) : kGlassFrostFill),
                borderRadius: borderRadius,
              ),
              // [FIX — No Material widget found] showDialog/showModalBottomSheet đẩy nội dung
              // vào Overlay của Navigator, KHÔNG phải hậu duệ của Scaffold/Material màn hình bên
              // dưới (khác Dialog() gốc vốn tự bọc Material). ListTile/InkResponse/InkWell bên
              // trong bất kỳ widget kính nào (card/dialog/dropdown...) sẽ crash đỏ nếu thiếu tổ
              // tiên Material. Vá TẠI ĐÂY (nơi DUY NHẤT dựng lớp kính) để mọi widget dùng
              // _GlassSurface đều được bọc — type: transparency để không vẽ đè lên hiệu ứng kính.
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  children: [
                    // [ĐỢT 13 — FIX VIỀN NHÂN ĐÔI] CustomPaint viền gradient hắt sáng này vẽ
                    // GẦN NHƯ TRÙNG biên với outerDecoration.border ở Container ngoài cùng phía
                    // trên (cùng bo góc, cùng rìa ngoài) — với mặt kính NỔI (inverted=false,
                    // card/dialog/sheet) outerDecoration ĐÃ có viền riêng rồi nên CustomPaint ở
                    // đây bị THỪA, tạo hiệu ứng 2 đường viền lồng nhau. CHỈ còn vẽ cho mặt kính
                    // CHÌM (inverted=true, form nhập liệu) — nơi outerDecoration KHÔNG có viền
                    // (xem outerDecoration ở trên) nên đây là viền DUY NHẤT của nó.
                    if (inverted)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _GlassBorderPainter(borderRadius: resolvedRadius, inverted: inverted)),
                        ),
                      ),
                    if (padding != null)
                      Padding(
                        padding: padding!,
                        child: DefaultTextStyle.merge(style: const TextStyle(shadows: kGlassTextShadow), child: child),
                      )
                    else
                      DefaultTextStyle.merge(style: const TextStyle(shadows: kGlassTextShadow), child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 🔲 APP SCAFFOLD
// ============================================================================
/// Thay `Scaffold(...)` — cùng bộ tham số cốt lõi nên đổi tên constructor là xong. AppBar/
/// BottomNav tự có lớp kính (blur+frost) bọc ngoài khi bật Glass, NHƯNG bạn vẫn phải tự đổi
/// `backgroundColor` của AppBar/BottomNavigationBar TRUYỀN VÀO thành trong suốt theo cùng cờ
/// `context.watch<ThemeProvider>().isGlassThemeEnabled` (Flutter không cho AppScaffold "mổ"
/// màu của 1 widget con tùy ý truyền vào) — ví dụ ÁP DỤNG THẬT: `lib/screens/dashboard_screen.dart`,
/// biến `isGlass` trong `build()` của `_DashboardScreenState`.
class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? drawer;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor; // dùng khi TẮT Glass — giữ nguyên hành vi Scaffold gốc

  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.drawer,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!_isGlass(context)) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: appBar,
        drawer: drawer,
        body: body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
      );
    }
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: appBar == null
          ? null
          // [BackdropFilter RIÊNG cho dải AppBar] hợp lệ về mặt hiệu năng vì đây là 1 dải
          // NGANG cố định, chiều cao nhỏ (kToolbarHeight) — khác hẳn việc lồng 2 _GlassSurface
          // toàn màn hình. Không dùng _GlassSurface ở đây để tránh bo góc (AppBar cần vuông).
          : PreferredSize(
              preferredSize: appBar!.preferredSize,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: kGlassBlurSigma, sigmaY: kGlassBlurSigma),
                  child: Container(color: kGlassFrostFill, child: appBar),
                ),
              ),
            ),
      drawer: drawer,
      body: Stack(
        children: [
          const Positioned.fill(child: _AuroraMeshBackground()),
          body,
        ],
      ),
      bottomNavigationBar: bottomNavigationBar == null
          ? null
          : ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: kGlassBlurSigma, sigmaY: kGlassBlurSigma),
                child: Container(color: kGlassFrostFill, child: bottomNavigationBar),
              ),
            ),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }
}

// ============================================================================
// 🃏 APP CONTAINER / APP CARD
// ============================================================================
/// Thay mọi `Container(decoration: BoxDecoration(color: cardColor, borderRadius: ...))` —
/// khối kính KHÔNG bấm được (panel nền, khối bọc nhóm nội dung).
class AppContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  // [margin] mặc định null (KHÔNG tự ý set 4.0) — mọi call site hiện có đều tự quản khoảng
  // cách giữa các thẻ bằng Padding/SizedBox/GridView spacing riêng ở màn hình gọi; đặt default
  // khác 0 ở đây sẽ CỘNG DỒN khoảng cách lên hàng chục chỗ đã có sẵn, phá pixel-parity khi tắt
  // Glass. Chỉ có hiệu lực khi caller CHỦ ĐỘNG truyền vào.
  final EdgeInsetsGeometry? margin;
  final double? width, height;
  final BorderRadius? borderRadius;
  final Color? color; // màu nền khi TẮT Glass (mặc định: surface theo sáng/tối hiện có)
  // [ĐỢT 9] Màu phủ TRỰC TIẾP lên mặt kính khi Glass BẬT (khác [color] — CHỈ áp dụng khi Glass
  // TẮT). Dùng cho các popup cần độ đục cao hơn mức frost mặc định để đảm bảo tương phản chữ
  // (vd menu Avatar trên nền Sáng Kính) — không đổi hành vi bất kỳ call site nào khác vì mặc
  // định null.
  final Color? glassTint;

  const AppContainer({super.key, required this.child, this.padding, this.margin, this.width, this.height, this.borderRadius, this.color, this.glassTint});

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    Widget result;
    if (!_isGlass(context)) {
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      result = Container(
        width: width,
        height: height,
        padding: padding ?? const EdgeInsets.all(16),
        // [ĐỢT 9/12 — ĐÁNH NỔI KHỐI] Container.clipBehavior chỉ clip CHILD theo hình decoration,
        // KHÔNG cắt boxShadow (decoration được DecoratedBox vẽ ở ngoài phần clip) — an toàn
        // thêm cả 2 cùng lúc. Đây LÀ nơi thẻ Nhà/Thống kê/Phòng (Bento) trên dashboard_screen.dart
        // đang dùng chung (AppContainer) — sửa giá trị TẠI ĐÂY áp dụng cho mọi thẻ đó cùng lúc.
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color ?? (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: radius,
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.2), width: 1),
          boxShadow: [
            isDark
                ? BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))
                : BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: child,
      );
    } else {
      result = _GlassSurface(
        borderRadius: radius,
        padding: padding ?? const EdgeInsets.all(16),
        width: width,
        height: height,
        frostOverride: glassTint,
        child: child,
      );
    }
    return margin != null ? Padding(padding: margin!, child: result) : result;
  }
}

/// Thẻ BẤM ĐƯỢC (thiết bị/phòng/ngữ cảnh) — thêm hiệu ứng "nén sáng" khi chạm (Phần 3).
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  // [margin] mặc định null — xem giải thích ở AppContainer.margin: call site đang tự quản
  // khoảng cách ngoài, đặt default 4.0 kiểu Card gốc sẽ cộng dồn lên UI đã lên hình.
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AppCard({super.key, required this.child, this.padding, this.margin, this.borderRadius, this.color, this.onTap, this.onLongPress});

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if ((widget.onTap == null && widget.onLongPress == null)) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(20);
    final bool glass = _isGlass(context);
    Widget result;

    if (!glass) {
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      // [ĐỢT 9 — ĐÁNH NỔI KHỐI] Material không có tham số boxShadow/border kiểu BoxDecoration
      // — bọc thêm 1 Container NGOÀI chỉ lo viền + đổ bóng (không màu nền), Material bên
      // trong vẫn giữ nguyên màu nền + InkWell ripple như cũ, đúng bán kính bo góc.
      result = Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.2), width: 1),
          boxShadow: [
            isDark
                ? BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))
                : BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: Material(
          color: widget.color ?? (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Padding(padding: widget.padding ?? const EdgeInsets.all(16), child: widget.child),
          ),
        ),
      );
    } else {
      // [NÉN SÁNG] Kính không dùng InkWell (splash tối màu phá vỡ hiệu ứng trong suốt) — tự
      // dựng phản hồi chạm bằng AnimatedScale + độ sáng viền, đúng cảm giác "ép kính" của iOS.
      result = GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _pressed ? 0.85 : 1.0,
            duration: const Duration(milliseconds: 110),
            child: _GlassSurface(
              borderRadius: radius,
              padding: widget.padding ?? const EdgeInsets.all(16),
              tint: widget.color,
              child: widget.child,
            ),
          ),
        ),
      );
    }

    return widget.margin != null ? Padding(padding: widget.margin!, child: result) : result;
  }
}

// ============================================================================
// 🖼️ APP ICON — Icon có bóng đổ trên kính (xem ghi chú kGlassIconShadow)
// ============================================================================
class AppIcon extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? color;
  const AppIcon(this.icon, {super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final bool glass = _isGlass(context);
    return Icon(icon, size: size, color: color, shadows: glass ? kGlassIconShadow : null);
  }
}

// ============================================================================
// 💬 APP DIALOG / APP BOTTOM SHEET — hàm imperative, KHÔNG phải Widget class
// ============================================================================
/// Thay `showDialog(...)`. Truyền [child] là NỘI DUNG dialog (không tự bọc Dialog/Material).
///
/// [maxWidth] — mặc định 420 (popup nhỏ: xác nhận/đổi tên/form...). Dialog LỚN/chia cột
/// (vd WindowsSettingsDialog — Row sidebar 240px + Expanded nội dung, tự khóa maxWidth 1000
/// bên trong build() của chính nó) BẮT BUỘC truyền [maxWidth] khớp với kích thước gốc của
/// nó — nếu không, ConstrainedBox 420 mặc định ở đây sẽ bóp Expanded về gần 0 width, vỡ
/// thành chữ xếp dọc từng ký tự (đã xảy ra thật với popup Cài đặt).
///
/// [contentPadding] — mặc định EdgeInsets.all(24) (giữ nguyên hành vi mọi popup hiện có).
/// Dialog TỰ vẽ padding/thẻ con riêng bên trong (vd add_device_dialog.dart — 4 thẻ tính năng
/// tự có padding+margin nội bộ, cộng thêm 24 mặc định ở đây sẽ bị double-padding, ép cột nội
/// dung hẹp lại "co cụm" dù viền ngoài popup thừa trắng) có thể truyền giá trị nhỏ hơn — CHỈ
/// popup đó đổi, mọi caller không truyền vẫn y hệt 24 như trước.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
  double? maxWidth,
  EdgeInsetsGeometry? contentPadding,
  // [GIAI ĐOẠN 112] Ghi đè TOÀN BỘ màu frost mặc định (kGlassFrostFill — CHỈ 5% trắng, quá
  // trong suốt trên nền Sáng+Kính) — cùng cơ chế `frostOverride`/`glassTint` đã dùng cho
  // AppContainer (ĐỢT 9, xem _buildUserAvatarMenu trong dashboard_screen.dart) nhưng trước đây
  // CHƯA lộ ra ở showAppDialog(), khiến MỌI popup dựng bằng showAppDialog() (kể cả
  // DeviceMenuHelper.showGenericDeviceMenu) không có đường nào tự tăng độ đục riêng. Mặc định
  // null -> HÀNH VI CŨ giữ nguyên 100% cho mọi call site chưa cần đến tham số này.
  Color? glassTint,
}) {
  final bool glass = context.read<ThemeProvider>().isGlassThemeEnabled;
  final EdgeInsetsGeometry effectivePadding = contentPadding ?? const EdgeInsets.all(24);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: glass ? 0.35 : 0.5),
    builder: (ctx) {
      if (!glass) {
        Widget content = Padding(padding: effectivePadding, child: child);
        // Nhánh KHÔNG kính vốn không hề có maxWidth mặc định (Dialog() gốc tự do theo màn
        // hình) — chỉ áp giới hạn khi caller CHỦ ĐỘNG truyền, giữ pixel-parity cho mọi dialog
        // hiện có chưa cần [maxWidth].
        if (maxWidth != null) {
          content = ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: content);
        }
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
          child: content,
        );
      }
      // Barrier đã tối sẵn — KHÔNG cần Aurora phía sau dialog (dialog nổi trên nền app đã
      // có Aurora của AppScaffold rồi); chỉ cần lớp kính nổi giữa màn hình.
      //
      // [FIX — Chữ vỡ layout/xếp dọc] Trả lại Dialog() CHUẨN của Flutter (backgroundColor
      // trong suốt để lộ kính) thay vì tự dựng Center+ConstrainedBox thô — Dialog() nội bộ tự
      // áp constraints mặc định `minWidth: 280` (qua _DefaultDialogConstraints của Material)
      // mà bản tự dựng trước đó KHÔNG có (minWidth ngầm định = 0). Nội dung không tự ép được
      // bề rộng riêng (Row/Column mainAxisSize.min, ít chữ/icon) có thể co về gần 0 width và
      // vỡ thành chữ xếp dọc từng ký tự — lỗi kinh điển khi thiếu sàn minWidth. maxWidth mặc
      // định 420, dialog lớn/chia cột truyền [maxWidth] riêng — 2 constraints (đây + minWidth
      // 280 của Dialog()) giao nhau thành [280, maxWidth].
      return Dialog(
        backgroundColor: Colors.transparent, // bắt buộc để lộ _GlassSurface bên trong
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth ?? 420, minWidth: 280),
          child: _GlassSurface(borderRadius: BorderRadius.circular(28), padding: effectivePadding, frostOverride: glassTint, child: child),
        ),
      );
    },
  );
}

/// Thay `showModalBottomSheet(...)`. Truyền [child] là NỘI DUNG (đã tự SafeArea nếu cần).
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isScrollControlled = true,
}) {
  final bool glass = context.read<ThemeProvider>().isGlassThemeEnabled;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      if (!glass) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(top: false, child: child),
        );
      }
      return _GlassSurface(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(top: false, child: child),
      );
    },
  );
}

// ============================================================================
// ⌨️ APP TEXT FIELD / APP DROPDOWN — khối kính "CHÌM" (inverted highlight)
// ============================================================================
/// Thay `TextField`/`TextFormField`. Glass mode: khung sunken (viền sáng đảo hướng) thay vì
/// nổi như AppCard — đúng cảm giác "khoét vào mặt kính" của ô nhập liệu thay vì "nổi lên".
///
/// [NÂNG CẤP — hỗ trợ Form đầy đủ] Lõi bên trong LUÔN là `TextFormField` (không còn
/// `TextField` trần) — khi không có `validator`/ancestor `Form`, hành vi giống hệt
/// `TextField` cũ 100% (validator mặc định null = luôn hợp lệ), nên KHÔNG phá bất kỳ chỗ
/// gọi hiện có nào. `validator`/`onSaved` chỉ thật sự chạy khi nằm trong 1 `Form` cha gọi
/// `formKey.currentState?.validate()`/`.save()` — đúng hợp đồng Form chuẩn Flutter.
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? labelText, hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final FormFieldValidator<String>? validator;
  final FormFieldSetter<String>? onSaved;
  final FocusNode? focusNode;
  final int? maxLength;
  final bool enabled;
  final bool autofocus;

  const AppTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.maxLines = 1,
    this.validator,
    this.onSaved,
    this.focusNode,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool glass = _isGlass(context);
    final Color textColor = glass ? Colors.white : (isDark ? Colors.white : const Color(0xFF0F172A));
    final Color hintColor = glass ? Colors.white70 : (isDark ? Colors.white54 : const Color(0xFF64748B));

    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSaved: onSaved,
      validator: validator,
      maxLines: maxLines,
      maxLength: maxLength,
      enabled: enabled,
      autofocus: autofocus,
      style: TextStyle(color: textColor, shadows: glass ? kGlassTextShadow : null),
      cursorColor: glass ? Colors.white : null,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        labelStyle: TextStyle(color: hintColor),
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        border: glass ? InputBorder.none : OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: !glass,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );

    if (!glass) return field;
    return _GlassSurface(borderRadius: BorderRadius.circular(16), padding: EdgeInsets.zero, inverted: true, child: field);
  }
}

/// Thay `DropdownButtonFormField` — dùng cho chọn thiết bị/kênh(endpoint)/loại lịch...
///
/// [CẢNH BÁO GOTCHA ĐÃ GẶP THẬT — DropdownButtonFormField.initialValue] Tham số `initialValue`
/// (bản Flutter dự án này dùng, thay `value:` cũ) CHỈ được đọc ĐÚNG 1 LẦN lúc FormFieldState
/// khởi tạo — KHÔNG tự đồng bộ lại khi [value]/[items] đổi ở lần build sau (khác `value:` đời
/// cũ vốn phản ứng mỗi rebuild). Nếu bạn dùng AppDropdown cho cascading dropdown (vd đổi
/// Thiết bị -> danh sách Kênh đổi theo), BẮT BUỘC truyền `key: ValueKey(...)` gắn với thứ
/// quyết định danh sách [items] (vd `ValueKey(selectedDeviceMac)`) để ép Flutter tạo lại
/// State mới mỗi khi đổi — thiếu bước này Dropdown sẽ render THÀNH HỘP TRẮNG RỖNG không chọn
/// được gì (đã xảy ra thật, xem [[schedule-endpoint-dropdown-white-box-fix]] trong lịch sử dự án).
class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? labelText;
  final Widget? prefixIcon;
  final FormFieldValidator<T>? validator;
  final FormFieldSetter<T>? onSaved;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelText,
    this.prefixIcon,
    this.validator,
    this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool glass = _isGlass(context);
    final Color textColor = glass ? Colors.white : (isDark ? Colors.white : const Color(0xFF0F172A));
    final Color hintColor = glass ? Colors.white70 : (isDark ? Colors.white54 : const Color(0xFF64748B));

    final field = DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      onSaved: onSaved,
      isExpanded: true,
      dropdownColor: glass ? const Color(0xFF2A2D45) : (isDark ? const Color(0xFF2A2D31) : Colors.white),
      style: TextStyle(color: textColor, fontSize: 14, shadows: glass ? kGlassTextShadow : null),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: hintColor),
        prefixIcon: prefixIcon,
        border: glass ? InputBorder.none : OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: !glass,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );

    if (!glass) return field;
    return _GlassSurface(borderRadius: BorderRadius.circular(16), padding: EdgeInsets.zero, inverted: true, child: field);
  }
}

// ============================================================================
// 🔘 APP SEGMENTED BUTTON / APP SWITCH — "nén sáng" khi chạm (Phần 3)
// ============================================================================
/// Thay `SegmentedButton<T>` — dùng cho tab Chạm-để-chạy/Tự động, Bật/Tắt, Giờ cố định/
/// Đếm ngược... Glass mode: viên thuốc kính, mục đang chọn sáng lên + nén nhẹ.
class AppSegmentedButton<T> extends StatelessWidget {
  final List<({T value, String label, IconData? icon})> segments;
  final Set<T> selected;
  final ValueChanged<T> onSelectionChanged;

  const AppSegmentedButton({super.key, required this.segments, required this.selected, required this.onSelectionChanged});

  @override
  Widget build(BuildContext context) {
    final bool glass = _isGlass(context);
    if (!glass) {
      return SegmentedButton<T>(
        segments: [
          for (final s in segments) ButtonSegment(value: s.value, icon: s.icon != null ? Icon(s.icon) : null, label: Text(s.label)),
        ],
        selected: selected,
        onSelectionChanged: (v) => onSelectionChanged(v.first),
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      );
    }

    return _GlassSurface(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in segments)
            Expanded(
              child: _GlassSegment(
                label: s.label,
                icon: s.icon,
                active: selected.contains(s.value),
                onTap: () => onSelectionChanged(s.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassSegment extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;
  const _GlassSegment({required this.label, this.icon, required this.active, required this.onTap});

  @override
  State<_GlassSegment> createState() => _GlassSegmentState();
}

class _GlassSegmentState extends State<_GlassSegment> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: widget.active ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: Colors.white, shadows: kGlassTextShadow),
                const SizedBox(width: 6),
              ],
              Text(widget.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, shadows: kGlassTextShadow)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thay `Switch` — công tắc bật/tắt thiết bị trên thẻ kính.
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  const AppSwitch({super.key, required this.value, required this.onChanged, this.activeColor});

  @override
  Widget build(BuildContext context) {
    final bool glass = _isGlass(context);
    if (!glass) {
      return Switch(value: value, onChanged: onChanged, activeThumbColor: activeColor ?? const Color(0xFF00A651));
    }
    // Track kính + thumb kính nổi hẳn (blur riêng của track qua _GlassSurface cha đã đủ —
    // thumb chỉ cần 1 khối trắng mờ có shadow, KHÔNG cần thêm BackdropFilter thứ 2).
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value ? (activeColor ?? const Color(0xFF00A651)).withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))],
          ),
        ),
      ),
    );
  }
}
