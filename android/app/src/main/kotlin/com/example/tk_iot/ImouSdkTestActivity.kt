package com.example.tk_iot

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.FrameLayout
import android.widget.TextView
import com.lechange.opensdk.api.InitParams
import com.lechange.opensdk.api.LCOpenSDK_Api
import com.lechange.opensdk.media.LCOpenSDK_ParamDeviceRecord
import com.lechange.opensdk.media.cloud.listener.LCOpenSDK_PlayBackListener
import com.lechange.opensdk.media.playback.LCOpenSDK_PlayBackWindow

/**
 * [XEM LẠI THẺ SD — PHA 1 XÁC MINH LCOpenSDK — CHỈ ĐỂ TEST, XÓA SAU KHI XONG PHA 1]
 *
 * Activity native THUẦN (không qua Flutter engine) — cố ý tách biệt để cô lập biến số: chỉ kiểm
 * tra bản thân LCOpenSDK có chạy đúng với dữ liệu THẬT của hệ thống hay không, trước khi viết
 * PlatformView/MethodChannel đầy đủ cho App thật.
 *
 * MỌI method/tham số dưới đây đã XÁC MINH THẬT — qua javap (decompile classes.jar bên trong
 * chính LCOpenSDK.aar bạn cung cấp) LẪN 2 file "Android OpenSDK/LCOpenMedia Protocol
 * document.docx" chính chủ Imou (thư mục E:\Software_Projects\SDK imou\...\) — KHÔNG đoán:
 *   - InitParams(Context, host, token) — 3 tham số, token là chuỗi String trần.
 *   - `host` PHẢI kèm CỔNG ngay trong chuỗi kiểu "domain:443" (mẫu tài liệu:
 *     "openapi.lechange.cn:443") — thiếu cổng khiến SDK rơi về HTTP cổng 80 mặc định (xác nhận
 *     thật: SocketTimeoutException cổng 80 lần chạy đầu, trong khi curl HTTPS cổng 443 từ chính
 *     điện thoại trả 200 OK bình thường).
 *   - LCOpenSDK_Api.initOpenApi(InitParams): Int, throws Throwable.
 *   - setCaInfo(0, "") — TẮT xác thực cert riêng của SDK (TrustAllX509TrustManager). Cert-pin
 *     bundle sẵn trong .aar này KHÔNG khớp cert THẬT của server (log thật: "no matcher after all
 *     search", CertificateException) — rất có thể do SDK build cũ hơn cert hiện tại của server.
 *     setCaInfo(0, "") giải quyết được (đã test thật, hết lỗi cert).
 *   - `playToken` [Optional] KHÔNG lấy qua getPlayTokenKeyEx (0 lần xuất hiện trong tài liệu —
 *     API không tài liệu hóa, test thật trả lỗi TK1002) — tài liệu ghi playToken lấy từ API
 *     listDeviceDetailsByPage, và thiếu/sai chỉ rơi về "old streaming protocol" chứ KHÔNG chặn
 *     phát — bỏ hẳn bước này, dùng playToken rỗng.
 *   - `psk` = "Decryption key (unencrypted input device serial number (S/N), the password set
 *     must be provided for encrypted video)" — ĐÚNG giả thuyết PSK = DeviceSerial cho video KHÔNG
 *     đặt mật khẩu riêng (trường hợp camera của ta).
 *   - `initPlayWindow(Context, ViewGroup, Int index, Boolean isUseSurfaceView)` — tài liệu xác
 *     nhận đúng ý nghĩa 2 tham số cuối: index=0 (id cửa sổ), isUseSurfaceView=false (dùng
 *     TextureView).
 *   - LCOpenSDK_ParamDeviceRecord 14 tham số ĐÚNG THỨ TỰ (dò bytecode constructor, không đoán):
 *     accessToken, deviceID, channelId, psk, playToken, fileId, startTime(ms), endTime(ms),
 *     offsetTime, definitionMode, isOpt, productId, tlsEnable, multiFlag.
 *
 * CÒN CHƯA XÁC MINH (sẽ lộ ra qua log khi chạy thật):
 *   - offsetTime/definitionMode/isOpt/productId — chưa rõ ý nghĩa/giá trị mặc định an toàn, tạm
 *     dùng 0/0/false/"" (rỗng), quan sát log nếu SDK từ chối.
 *
 * [CẦN THAY TRƯỚC KHI CHẠY] 3 hằng số RECORD_FILE_ID/RECORD_START_MS/RECORD_END_MS đang là
 * placeholder rỗng — PHẢI có 1 đoạn ghi THẬT trên thẻ SD camera trước (bật ghi hình liên tục/theo
 * chuyển động qua App Imou Life, đợi vài phút có ghi hình) rồi lấy fileId+thời gian thật (Claude
 * sẽ chạy lại cmd/imousdktest phía Backend để lấy giúp khi bạn báo đã có ghi hình).
 */
class ImouSdkTestActivity : Activity() {

    // ---- DỮ LIỆU THẬT lấy từ Backend (cmd/imousdktest) — thay khi có bản mới ----
    private val ACCESS_TOKEN = "At_0000sgdfa8d622d16941fa84be01949f"
    private val DEVICE_SERIAL = "6G00644PAZED884"
    private val CHANNEL_ID = 0
    // [FIX — ĐÃ XÁC MINH qua "Android OpenSDK Protocol document.docx" chính chủ Imou] host PHẢI
    // kèm CỔNG ngay trong chuỗi (mẫu tài liệu: "openapi.lechange.cn:443") — thiếu ":443" khiến
    // SDK rơi về mặc định HTTP cổng 80 (đã xác nhận thật: SocketTimeoutException cổng 80, trong
    // khi curl HTTPS cổng 443 từ chính điện thoại trả 200 OK bình thường).
    private val HOST = "openapi-sg.easy4ip.com:443"

    // ---- Đoạn ghi THẬT lấy từ Backend hôm nay (2026-07-23), camera 6G00644PAZED884 ----
    private val RECORD_FILE_ID = "/mnt/sd/mmcblk0p0/2026-07-23/001/dav/01/01.16.36-01.17.17[M][0@0][0].dav"
    private val RECORD_START_MS = 1784744196000L
    private val RECORD_END_MS = 1784744237000L

    private lateinit var logView: TextView
    private lateinit var playContainer: FrameLayout
    private val mainHandler = Handler(Looper.getMainLooper())
    private val logBuilder = StringBuilder()

    private fun log(line: String) {
        android.util.Log.d("ImouSdkTest", line)
        logBuilder.append(line).append('\n')
        mainHandler.post { logView.text = logBuilder.toString() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_imou_sdk_test)
        logView = findViewById(R.id.log_view)
        playContainer = findViewById(R.id.play_container)
        logBuilder.clear()

        Thread { runTest() }.start()
    }

    private fun runTest() {
        // [THỬ NGHIỆM — cert-pin cũ trong SDK không khớp cert THẬT của server, xem log
        // "no matcher after all search"] setCaInfo(0, "") thử TẮT xác thực cert riêng của SDK
        // (TrustAllX509TrustManager) — tên lớp gợi ý mặc định là "trust tất cả", nhưng log thật
        // cho thấy verifyCertificate() VẪN chạy — thử ép caSwitch=0 xem có bỏ qua được không.
        log("== BƯỚC 0: setCaInfo(0, \"\") — thử tắt xác thực cert riêng của SDK ==")
        try {
            LCOpenSDK_Api.setCaInfo(0, "")
        } catch (t: Throwable) {
            log("setCaInfo lỗi (bỏ qua, thử tiếp): ${t.message}")
        }

        log("== BƯỚC 1: initOpenApi (host=$HOST) ==")
        try {
            val code = LCOpenSDK_Api.initOpenApi(InitParams(applicationContext, HOST, ACCESS_TOKEN))
            log("initOpenApi trả về code=$code (kỳ vọng 0 = thành công)")
            if (code != 0) {
                log("!! initOpenApi KHÔNG trả 0 — token/host có thể sai, DỪNG Ở ĐÂY")
                return
            }
        } catch (t: Throwable) {
            log("!! initOpenApi NÉM EXCEPTION: ${t.javaClass.simpleName}: ${t.message}")
            return
        }

        // [BỎ getPlayTokenKeyEx — KHÔNG có trong tài liệu chính chủ] Doc thật ghi playToken lấy
        // từ API listDeviceDetailsByPage (danh sách thiết bị), KHÔNG PHẢI getPlayTokenKeyEx (0 lần
        // xuất hiện trong toàn bộ "Android OpenSDK Protocol document.docx") — và playToken là
        // [Optional] (thiếu chỉ rơi về "old streaming protocol", không chặn phát). Đi thẳng vào
        // playback với playToken rỗng, đúng theo tài liệu thay vì dựa vào API không tài liệu hóa.
        mainHandler.post { onPlayTokenReady("") }
    }

    private fun onPlayTokenReady(playToken: String) {
        if (RECORD_FILE_ID.isEmpty()) {
            log("== BƯỚC 2: BỎ QUA (chưa có RECORD_FILE_ID thật) ==")
            log("initOpenApi đã xác nhận PASS. Điền RECORD_FILE_ID/START/END rồi chạy lại để test playRecordStream + PSK thật.")
            return
        }

        log("== BƯỚC 2: playRecordStream (fileId=$RECORD_FILE_ID, psk=$DEVICE_SERIAL) ==")
        val playBackWindow = LCOpenSDK_PlayBackWindow()
        // [THỬ LẦN 2 — lần 1 isUseSurfaceView=false (TextureView) chạy 46s chỉ ra onPlayFinished,
        // KHÔNG BAO GIỜ onPlayBegin/onPlayLoading] Đổi sang true (SurfaceView) — một số bản SDK
        // Trung Quốc decode cứng chỉ hoạt động ổn định qua SurfaceView, đường TextureView có thể
        // có bug/thiếu init nội bộ khiến luồng không bao giờ thực sự bắt đầu dù bắt tay HTTP OK.
        playBackWindow.initPlayWindow(this, playContainer, 0, true)
        playBackWindow.setPlayBackListener(object : LCOpenSDK_PlayBackListener() {
            override fun onPlayBegin(handle: Int, deviceId: String?) {
                log("*** onPlayBegin — PHÁT THÀNH CÔNG (deviceId=$deviceId) ***")
            }
            override fun onPlayLoading(handle: Int) {
                log("onPlayLoading...")
            }
            override fun onPlayFail(handle: Int, deviceId: String?, errorCode: String?, extra: Int) {
                log("!! onPlayFail — deviceId=$deviceId errorCode=$errorCode extra=$extra")
            }
            override fun onPlayFinished(handle: Int, deviceId: String?) {
                log("onPlayFinished — deviceId=$deviceId")
            }
        })

        // [PSK GIẢ THUYẾT — xem ghi chú đầu file] psk = DEVICE_SERIAL, chưa xác nhận thật.
        // offsetTime=0, definitionMode=0 (HG theo LCOpenSDK_ParamReal.DEFINITION_MODE ordinal 0),
        // isOpt=false, productId="", tlsEnable=false, multiFlag=false — TẤT CẢ tạm mặc định an
        // toàn, chưa xác nhận ý nghĩa/giá trị đúng.
        val param = LCOpenSDK_ParamDeviceRecord(
            ACCESS_TOKEN, DEVICE_SERIAL, CHANNEL_ID, DEVICE_SERIAL, playToken,
            RECORD_FILE_ID, RECORD_START_MS, RECORD_END_MS,
            0, 0, false, "", false, false
        )
        playBackWindow.playRecordStream(param)
    }
}
