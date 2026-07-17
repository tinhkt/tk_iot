# Icon thời tiết động (Lottie)

Thư mục này giữ chỗ cho các file Lottie `.json` mà `getWeatherIcon()` (`lib/screens/dashboard_screen.dart`)
đang tham chiếu tới. **Chưa có file thật nào ở đây** — cho tới khi bạn thả file `.json` đúng tên vào,
`getWeatherIcon()` sẽ tự rơi về `errorBuilder` (icon tĩnh `Icons.cloud`/tương ứng), không crash app.

Tên file game cần khớp CHÍNH XÁC (phân biệt hoa/thường):

| File cần thêm      | Dùng khi nhóm thời tiết (OpenWeatherMap `weather[0].main`) là |
|---------------------|----------------------------------------------------------------|
| `clear.json`        | `Clear`                                                         |
| `clouds.json`        | `Clouds`                                                        |
| `rain.json`          | `Rain`, `Drizzle`                                               |
| `storm.json`         | `Thunderstorm`                                                  |
| `snow.json`          | `Snow`                                                          |
| `mist.json`          | `Mist`, `Fog`, `Haze`                                           |

Gợi ý nguồn Lottie miễn phí: [LottieFiles](https://lottiefiles.com) (tìm "weather icons pack") —
tải về, đổi tên đúng bảng trên, thả vào thư mục này, chạy lại `flutter pub get` là xong — không cần sửa code.
