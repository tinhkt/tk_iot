import 'package:flutter/material.dart';

class SpinningWidget extends StatefulWidget {
  final Widget child;
  final bool isSpinning;
  final int speedLevel; // Truyền tốc độ quạt vào đây (tùy chọn)

  const SpinningWidget({
    super.key,
    required this.child,
    required this.isSpinning,
    this.speedLevel = 1,
  });

  @override
  _SpinningWidgetState createState() => _SpinningWidgetState();
}

class _SpinningWidgetState extends State<SpinningWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Khởi tạo bộ đếm thời gian xoay (Mặc định 1 giây/vòng)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isSpinning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(SpinningWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Nếu trạng thái đổi từ Tắt -> Bật
    if (widget.isSpinning && !oldWidget.isSpinning) {
      _controller.repeat();
    } 
    // Nếu trạng thái đổi từ Bật -> Tắt
    else if (!widget.isSpinning && oldWidget.isSpinning) {
      _controller.stop();
    }

    // (Nâng cao): Đổi tốc độ xoay dựa trên số quạt (1, 2, 3)
    if (widget.isSpinning && widget.speedLevel != oldWidget.speedLevel) {
      int durationMs = 1000;
      if (widget.speedLevel == 2) durationMs = 700;
      if (widget.speedLevel == 3) durationMs = 400; // Càng nhỏ xoay càng nhanh
      _controller.duration = Duration(milliseconds: durationMs);
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: widget.child, // Trả lại icon quạt nguyên bản của bác
    );
  }
}