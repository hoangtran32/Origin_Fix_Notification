# Hướng dẫn sử dụng

## 1. Chuẩn bị

1. Dùng máy tính Windows có PowerShell.
2. Nếu chưa có ADB trong `PATH`, tải [SDK Platform-Tools cho Windows](https://developer.android.com/tools/releases/platform-tools), giải nén rồi chép `adb.exe`, `AdbWinApi.dll` và `AdbWinUsbApi.dll` vào thư mục `tools`.
3. Trên điện thoại, bật **Tùy chọn nhà phát triển → Gỡ lỗi USB**.
4. Kết nối điện thoại với máy tính bằng cáp USB có truyền dữ liệu.
5. Mở khóa điện thoại, chọn **Cho phép** khi xuất hiện yêu cầu gỡ lỗi USB.
6. Chỉ kết nối một điện thoại khi chạy công cụ.

## 2. Kiểm tra trạng thái

1. Mở thư mục `tools`.
2. Nhấp đúp `1_KIEM_TRA_TRANG_THAI.bat`.
3. Kiểm tra tên thiết bị, danh sách user và các ứng dụng được phát hiện.
4. Đọc kết quả của từng ứng dụng, gồm cả bản gốc và bản nhân bản.
5. Nhấn Enter khi cửa sổ yêu cầu để kết thúc.

## 3. Áp dụng thiết lập

1. Nhấp đúp `tools/CHAY_CONG_CU_FIX_THONG_BAO.bat`.
2. Nhập `2` tại menu rồi nhấn Enter.
3. Chờ công cụ tạo bản sao lưu; ghi lại tên file JSON được hiển thị. File JSON và TXT nằm trong `tools/backups`.
4. Chọn phạm vi:
   - Nhập `A` để chọn toàn bộ danh sách được phát hiện.
   - Nhập `S` để chọn từng ứng dụng, sau đó nhập các số thứ tự cách nhau bằng dấu phẩy, ví dụ `1,2,4`. Chọn riêng các dòng của bản gốc và bản nhân bản cần xử lý.
5. Tại câu hỏi quyền nâng cao, nhập `Y` để áp dụng cả hai quyền chạy nền, cửa sổ nổi, cuộc gọi toàn màn hình và tắt tự thu hồi quyền; nhập `N` để bỏ qua nhóm này. Nhấn Enter không nhập gì tương đương `Y`.
6. Chờ xử lý xong và đọc kết quả từng ứng dụng.
7. Nhấn Enter để trở lại menu; nhập `5` để thoát.

## 4. Thiết lập trên điện thoại

Thực hiện riêng cho mỗi ứng dụng gốc và nhân bản cần nhận thông báo:

1. Bật **Tự khởi động** và **Khởi động liên kết** trong phần quyền ứng dụng.
2. Trong phần quản lý pin, chọn **Cho phép tiêu hao pin nền cao** hoặc **Không hạn chế**, tùy tên mục trên máy.
3. Cho phép sử dụng dữ liệu di động trong nền; kiểm tra quyền dùng dữ liệu khi bật chế độ tiết kiệm dữ liệu.
4. Bật thông báo của ứng dụng và các kênh tin nhắn/cuộc gọi cần dùng. Bật hiển thị trên màn hình khóa và biểu ngữ nổi nếu cần.
5. Kiểm tra cài đặt thông báo bên trong ứng dụng và từng cuộc trò chuyện.
6. Mở ứng dụng, vào đa nhiệm rồi khóa thẻ ứng dụng bằng tùy chọn ổ khóa.
7. Sau khi khởi động lại điện thoại, mở các ứng dụng cần nhận thông báo một lần.
8. Gửi thử tin nhắn mới vào từng tài khoản khi ứng dụng ở nền. Thử tiếp khi màn hình tắt, trên Wi-Fi và 4G/5G.

## 5. Hoàn tác theo bản sao lưu

1. Giữ file JSON cần dùng trong `tools/backups`; nếu đã chuyển backup ra ngoài, chép lại file trước khi chạy.
2. Kết nối đúng điện thoại đã tạo bản sao lưu.
3. Mở `tools/CHAY_CONG_CU_FIX_THONG_BAO.bat`, nhập `3`.
4. Chọn số thứ tự của bản sao lưu cần dùng rồi nhấn Enter.
5. Chờ xử lý xong, chạy lại `1_KIEM_TRA_TRANG_THAI.bat` và đối chiếu với bản sao lưu.

Để dùng ngay bản sao lưu mới nhất của điện thoại đang kết nối, chạy `tools/3_KHOI_PHUC_HOAN_TAC.bat`.

## 6. Kiểm tra kết nối Google

1. Kết nối điện thoại với máy tính.
2. Nhấp đúp `tools/4_KIEM_TRA_KET_NOI_FCM.bat`, hoặc chọn `4` trong menu chính.
3. Đọc trạng thái kết nối và các sự kiện có thời gian ghi nhận.
4. Khi kiểm tra lỗi mất thông báo, ghi lại giờ gửi tin, ứng dụng, bản gốc/nhân bản, loại mạng và trạng thái màn hình. Lấy kết quả trước khi mở lại ứng dụng đang lỗi.

## 7. Khi không tìm thấy điện thoại

1. Kiểm tra cáp, cổng USB, gỡ lỗi USB và yêu cầu cấp phép trên điện thoại.
2. Nếu đã chép ADB vào `tools`, mở PowerShell tại thư mục đó và chạy `./adb.exe devices`. Nếu dùng ADB trong `PATH`, chạy `adb devices`.
3. Nếu trạng thái là `unauthorized`, mở khóa điện thoại và chọn **Cho phép**.
4. Nếu danh sách trống, đổi cáp/cổng USB và kiểm tra driver USB của điện thoại.
5. Nếu có nhiều thiết bị, ngắt các thiết bị còn lại rồi chạy lại công cụ.
