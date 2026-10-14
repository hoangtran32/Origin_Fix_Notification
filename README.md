# Công cụ thông báo Vivo / iQOO OriginOS

Công cụ ADB cho Windows: kiểm tra trạng thái, chọn ứng dụng và user, xem đề xuất, sao lưu từng thay đổi, áp dụng và xác minh, hoàn tác. Mã nguồn chạy trên Windows PowerShell 5.1 trở lên. Tương thích thực tế còn tùy phiên bản Android/OriginOS và quyền ADB của máy.

## 1. Chuẩn bị và chạy nhanh

1. Bật **Tùy chọn nhà phát triển → Gỡ lỗi USB**, cắm cáp dữ liệu, mở khóa và chọn **Cho phép**.
2. Mở `tools/CHAY_CONG_CU_FIX_THONG_BAO.bat`, hoặc các nút chạy nhanh:

| Tệp | Tác dụng |
| --- | --- |
| `1_KIEM_TRA_TRANG_THAI.bat` | Audit; chỉ đọc điện thoại |
| `2_TOI_UU_THONG_BAO.bat` | Chọn app/user, xem đề xuất rồi áp dụng |
| `3_KHOI_PHUC_HOAN_TAC.bat` | Hoàn tác nhật ký mới nhất còn thay đổi chưa khôi phục |
| `4_KIEM_TRA_KET_NOI_FCM.bat` | Trạng thái FCM hiện tại và sự kiện gần nhất |
| `5_KIEM_TRA_AP_DUNG_LAI.bat` | Đọc lại hồ sơ đã chọn và đề xuất phần cần áp dụng lại |

Nếu thiếu ADB, tải [SDK Platform-Tools cho Windows](https://developer.android.com/tools/releases/platform-tools), chép `adb.exe`, `AdbWinApi.dll`, `AdbWinUsbApi.dll` vào cạnh script hoặc dùng ADB trong `PATH`. Khi có nhiều thiết bị, công cụ yêu cầu chọn đúng máy; CLI tự động cần `-Serial`.

## 2. Chọn đúng ứng dụng và tài khoản

Menu giữ các mục 1–5, thêm **6: mở cài đặt đúng app/user**, **7: kiểm tra và áp dụng lại hồ sơ**.

Nếu quét tự động gặp `Shell does not have permission to access user ...`, công cụ cảnh báo và bỏ qua user đó, tiếp tục với các user ADB truy cập được. Ví dụ trên máy có user `666` (XSpace User) bị chặn, user `0` và `999` vẫn được quét nếu có quyền. Báo cáo Audit lưu phạm vi trong `UserScan`, đánh dấu `UserScanComplete=false`; đây là kết quả kiểm tra một phần. Không suy ra user bị chặn không có ứng dụng. Khi chỉ định `-UserId` hoặc áp dụng lại hồ sơ có user bị chặn, công cụ dừng báo lỗi trước khi sửa; không tự chuyển sang user khác. Nếu tất cả user đều bị chặn, công cụ báo không thể quét. Lỗi kết nối/timeout và lỗi ADB khác vẫn được báo lỗi.

1. Chọn **2**, nhập số của từng dòng ứng dụng/user, ví dụ `1,3`. `A` chọn tất cả; Enter hủy. Tên user lấy từ thiết bị; user khác 0 không mặc định bị gọi là bản nhân bản.
2. Chọn riêng nhu cầu **cuộc gọi toàn màn hình**, **cửa sổ nổi** và **Google Play Services**. Các mục này mặc định tắt.
3. Đọc từng đề xuất trước khi xác nhận `Y`; Enter mặc định hủy.
4. Công cụ lưu JSON/TXT vào `backups` cạnh script trước lệnh thay đổi đầu tiên. Báo cáo nằm ở `reports`.
5. Đọc kết quả xác minh từng mục và hướng dẫn còn phải thao tác trên điện thoại.

Thiết lập cơ bản gồm full Doze, standby bucket theo user, miễn trừ Data Saver theo UID, quyền thông báo runtime khi Android API ≥ 33 và app đã khai báo quyền, cùng các AppOps liên quan thông báo/chạy nền. Bucket `EXEMPTED (5)` đã có được giữ nguyên. `RUN_IN_BACKGROUND` và `RUN_ANY_IN_BACKGROUND` đều được theo dõi.

Các miễn trừ có thể tăng pin và dữ liệu nền; chọn những app cần nhận thông báo.

**Phạm vi dùng chung:** Doze áp dụng theo package cho các user; NetPolicy áp dụng theo UID và có thể ảnh hưởng các app dùng chung UID. Công cụ loại trùng các mục này, kiểm tra UID trước khi sửa và không ghi khi chưa biết trạng thái gốc. AppOps ở cấp UID được báo chưa hỗ trợ tự động để tránh mất phạm vi ban đầu.

NetPolicy là miễn trừ **Data Saver trên mạng tính phí**, không chứng minh chữa được socket MQTT hoặc mọi tình trạng trễ tin. [Tài liệu Android](https://developer.android.com/develop/connectivity/network-ops/data-saver). Quyền runtime `POST_NOTIFICATIONS` riêng với AppOp và được kiểm tra từ Android 13; việc áp dụng lưu cả trạng thái cấp quyền, flags và AppOp để hoàn tác. [Tài liệu quyền thông báo](https://developer.android.com/develop/ui/compose/notifications/notification-permission).

## 3. Đọc kết quả và kiểm tra trên máy

- `Verified`: lệnh thành công và đọc lại đúng giá trị đề xuất.
- `AlreadySatisfied`: đã đúng, không gửi lệnh thay đổi.
- `Skipped`: trạng thái gốc không đọc được/không hỗ trợ; xem `ReadStatus` và `Detail`.
- `Failed`: lệnh lỗi hoặc xác minh không khớp.
- `Uncertain`: đã gửi lệnh nhưng không đọc lại được.
- `Conflict`: UID hoặc trạng thái đã đổi; công cụ không ghi đè.

Audit phân biệt trạng thái quyền, lỗi truy vấn, app `stopped`/disabled, Data Saver và Không làm phiền. `default` là giá trị AppOp thực; không tự coi là lỗi hoặc đã được phép. Thiếu dữ liệu được ghi rõ thay vì báo thành công.

Trên từng app/user, kiểm tra **Tự khởi động**, **Khởi động liên kết**, **Cho phép pin nền cao/Không hạn chế**, dữ liệu nền, các **kênh tin nhắn/cuộc gọi**, màn hình khóa, biểu ngữ, Không làm phiền và cài đặt thông báo trong app/cuộc trò chuyện. Mục 6 gửi yêu cầu mở cài đặt thông báo của đúng user, có màn hình thông tin app dự phòng; nếu OriginOS không hỗ trợ thì làm thủ công.

Nếu app đang `stopped`, mở đúng app/user một lần rồi thử lại. Khóa thẻ đa nhiệm nếu máy hỗ trợ. Sau reboot, Audit lại trước khi dùng mục 7. Các tùy chọn/kênh riêng của OriginOS chưa được tự động sửa hoặc xác minh.

## 4. Hoàn tác và áp dụng lại

Nhật ký **schema 2** lưu từng mục trước/sau, user/UID, trạng thái đọc, kết quả lệnh và xác minh. Ý định được ghi xuống đĩa trước lệnh sửa, nên vẫn có thể nhận diện lệnh đang dở nếu chương trình bị dừng. Hoàn tác chạy ngược thứ tự và chỉ xử lý các mục đã gửi lệnh, gồm thay đổi GMS, runtime permission/flags và AppOps `default`. Không dùng `appops reset`.

Dùng menu **3** để chọn nhật ký, hoặc nút chạy nhanh để lấy nhật ký mới nhất còn mục chưa khôi phục. Serial phải trùng thiết bị. Nếu app bị cài lại làm đổi UID hoặc bạn đã đổi giá trị sau khi chạy tool, công cụ báo xung đột để bạn đối chiếu; không cưỡng ép hoàn tác. Khi đã áp dụng nhiều lượt, hoàn tác từ lượt mới nhất về lượt cũ hơn.

**Backup cũ không có schema 2 vẫn được giữ nguyên, nhưng bị từ chối hoàn tác tự động** vì không ghi nhận mục thực sự đã sửa và không lưu đầy đủ trạng thái ban đầu. Dùng chúng để đối chiếu thủ công; việc tạo backup mới không khôi phục được trạng thái gốc đã thiếu trong backup cũ.

Mục **7** và `5_KIEM_TRA_AP_DUNG_LAI.bat` dùng `backups/profile_<serial>.json`: quét lại đúng các cặp package/user đã chọn, chỉ đề xuất các giá trị bị đổi. Mỗi lần có thay đổi tạo nhật ký riêng; hồ sơ giữ đường dẫn nhật ký đầu tiên và lịch sử các lượt. Không áp dụng lại tự động khi máy khởi động.

## 5. CLI

Chạy từ thư mục dự án bằng PowerShell. Package tùy chỉnh ngoài danh mục cũng dùng được. Danh sách package/user có thể truyền thành chuỗi phân cách bởi dấu phẩy khi gọi `powershell.exe -File`.

Trong bộ ZIP độc lập, script nằm ngay cạnh các tệp BAT: thay `.\tools\VivoNotificationFixer.ps1` trong ví dụ bằng `.\VivoNotificationFixer.ps1`.

```powershell
# Chỉ đọc, đúng bản nhân bản
.\tools\VivoNotificationFixer.ps1 -Audit -TargetPackage com.facebook.orca -UserId 999 -NoPrompt

# Xem đề xuất cho cả hai user; không thay đổi điện thoại
.\tools\VivoNotificationFixer.ps1 -Fix -PlanOnly -TargetPackage com.facebook.orca -UserId '0,999' -NoPrompt

# Áp dụng cơ bản vào user đã chỉ định; -NoPrompt bỏ bước xác nhận
.\tools\VivoNotificationFixer.ps1 -Fix -TargetPackage com.facebook.orca -UserId 999 -NoPrompt

# Thêm nhu cầu riêng khi cần
.\tools\VivoNotificationFixer.ps1 -Fix -TargetPackage com.facebook.orca -UserId 999 -Calls -Overlay -IncludeGoogleServices

# Đọc lại hồ sơ và chỉ xem đề xuất
.\tools\VivoNotificationFixer.ps1 -Reapply -PlanOnly -NoPrompt

# Hoàn tác nhật ký cụ thể
.\tools\VivoNotificationFixer.ps1 -Restore -BackupFile '.\tools\backups\backup_SERIAL_TIME.json' -NoPrompt

# Mở cài đặt đúng app/user
.\tools\VivoNotificationFixer.ps1 -OpenSettings -TargetPackage com.facebook.orca -UserId 999
```

`-AdvancedPermissions` được giữ để tương thích CLI: bật cuộc gọi, cửa sổ nổi và tắt tự thu hồi quyền. Mặc định tắt; chỉ dùng khi cần. `-Fix -NoPrompt` bắt buộc có cả package và user. Chỉ chọn một chế độ mỗi lượt. Mã thoát: `0` hoàn tất chế độ, `1` lỗi đầu vào/kết nối/backup, `2` Audit bỏ qua user không truy cập được, Fix/Restore còn mục chưa đạt hoặc FCM chưa xác định. Mã `0` không chứng minh nhận thông báo nền thành công.

## 6. FCM và bài thử nhận tin

FCM chỉ đọc trường hiện tại trong khối `Client:`. `Disconnected`, dòng `Connected` trong lịch sử và dữ liệu mâu thuẫn không bị nhận nhầm là đang kết nối. Có trạng thái `Connected`, `Disconnected`, `Unknown`; báo cáo giữ thời điểm đọc và đầu ra lệnh.

Để kiểm chứng hiệu quả: thử trước/sau cùng điều kiện, màn hình tắt **15–30 phút**, Wi-Fi, di động và chuyển mạng, riêng từng tài khoản gốc/nhân bản. Ghi giờ gửi và giờ thông báo thật xuất hiện; lấy Audit/FCM trước khi mở app. Thử lại sau reboot. Thời gian `Successful broadcast ... time=...` chỉ đo một bước giao FCM, không đo toàn bộ độ trễ hay chứng minh thông báo đã hiển thị.

## 7. Kiểm thử và đóng gói

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\NotificationFixer.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1
```

Bộ kiểm thử chạy ADB giả lập trong bộ nhớ, không thay đổi điện thoại. Đóng gói tạo thư mục sạch trong `dist`, chỉ đưa các file cho phép vào ZIP và kiểm tra không có `logs`, `backups`, `reports`. ZIP cũ được lưu trong `dist/previous`; thư mục phát hành tại gốc được cập nhật các file công cụ, giữ dữ liệu người dùng đang có. Không chia sẻ log/backup chứa định danh thiết bị khi chưa kiểm tra.

## 8. Setting email

1. Mở ứng dụng **Gmail**, nhấn biểu tượng menu ba dấu gạch ngang (☰) ở góc trên bên trái.
2. Cuộn xuống dưới cùng, chọn **Cài đặt** (Settings).
3. Chọn tài khoản email cần thiết lập.
4. Kiểm tra mục **Loại hộp thư đến** và đặt **Thông báo** thành **Tất cả email**.
5. Nhấn **Thông báo trong hộp thư đến**.
6. Bật **Thông báo nhãn**; chọn **Đồng ý** nếu có yêu cầu bật thông báo tài khoản.
7. Bật **Thông báo đối với mọi thư** để nhận âm thanh/rung khi có thư mới.

## Ủng hộ ly cà phê ☕

Nếu công cụ hữu ích, bạn có thể ủng hộ mình một ly cà phê.

- **Ngân hàng:** Techcombank
- **Số tài khoản:** `31080688888888`

## Nhận code tool auto, MMO

Nhận viết các loại tool tự động hóa (auto) và tool MMO theo yêu cầu.
