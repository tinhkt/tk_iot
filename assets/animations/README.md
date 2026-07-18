# Ảnh động Digital Twin (Lottie)

Thư mục này giữ chỗ cho các file Lottie `.json` mà 3 thẻ "Digital Twin" (`lib/widgets/digital_twin_cards.dart`)
đang tham chiếu tới. **Chưa có file thật nào ở đây** — cho tới khi bạn thả file `.json` đúng tên vào,
mỗi thẻ sẽ tự rơi về hình vẽ CustomPainter thay thế (nan cửa cuốn / cánh quạt bơm tự vẽ tay),
không crash app và vẫn đúng chức năng.

Tên file cần khớp CHÍNH XÁC (phân biệt hoa/thường):

| File cần thêm         | Dùng cho                                                        |
|------------------------|------------------------------------------------------------------|
| `rolling_door.json`   | SmartRollingDoorCard — mô phỏng nan cửa cuốn lên/xuống           |
| `pump.json`           | SmartPumpCard — mô phỏng cánh quạt/mô-tơ bơm đang quay            |

Gợi ý nguồn Lottie miễn phí: [LottieFiles](https://lottiefiles.com) — tải về, đổi tên đúng bảng
trên, thả vào thư mục này, chạy lại `flutter pub get` là xong — không cần sửa code.

Lưu ý: SmartDimmerCard (Đèn Chiết áp) KHÔNG dùng Lottie — vòng xoay Rotary Knob vẽ hoàn toàn
bằng CustomPainter (`_DimmerRingPainter`) vì cần tương tác vuốt xoay chính xác theo góc, không
phù hợp với ảnh động cố định.
