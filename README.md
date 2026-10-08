1. Chuẩn bị
 * Dùng máy tính Windows có PowerShell.
 * Nếu chưa có ADB trong PATH, tải SDK Platform-Tools cho Windows, giải nén rồi chép adb.exe, AdbWinApi.dll và AdbWinUsbApi.dll vào thư mục tools.
 * Trên điện thoại, bật Tùy chọn nhà phát triển → Gỡ lỗi USB.
 * Kết nối điện thoại với máy tính bằng cáp USB có truyền dữ liệu.
 * Mở khóa điện thoại, chọn Cho phép khi xuất hiện yêu cầu gỡ lỗi USB.
 * Chỉ kết nối một điện thoại khi chạy công cụ.
2. Kiểm tra trạng thái
 * Mở thư mục tools.
 * Nhấp đúp 1_KIEM_TRA_TRANG_THAI.bat.
 * Kiểm tra tên thiết bị, danh sách user và các ứng dụng được phát hiện.
 * Đọc kết quả của từng ứng dụng, gồm cả bản gốc và bản nhân bản.
 * Nhấn Enter khi cửa sổ yêu cầu để kết thúc.
3. Áp dụng thiết lập
 * Nhấp đúp tools/CHAY_CONG_CU_FIX_THONG_BAO.bat.
 * Nhập 2 tại menu rồi nhấn Enter.
 * Chờ công cụ tạo bản sao lưu; ghi lại tên file JSON được hiển thị. File JSON và TXT nằm trong tools/backups.
 * Chọn phạm vi:
   * Nhập A để chọn toàn bộ danh sách được phát hiện.
   * Nhập S để chọn từng ứng dụng, sau đó nhập các số thứ tự cách nhau bằng dấu phẩy, ví dụ 1,2,4. Chọn riêng các dòng của bản gốc và bản nhân bản cần xử lý.
 * Tại câu hỏi quyền nâng cao, nhập Y để áp dụng cả hai quyền chạy nền, cửa sổ nổi, cuộc gọi toàn màn hình và tắt tự thu hồi quyền; nhập N để bỏ qua nhóm này. Nhấn Enter không nhập gì tương đương Y.
 * Chờ xử lý xong và đọc kết quả từng ứng dụng.
 * Nhấn Enter để trở lại menu; nhập 5 để thoát.
4. Thiết lập trên điện thoại
Thực hiện riêng cho mỗi ứng dụng gốc và nhân bản cần nhận thông báo:
 * Bật Tự khởi động và Khởi động liên kết trong phần quyền ứng dụng.
 * Trong phần quản lý pin, chọn Cho phép tiêu hao pin nền cao hoặc Không hạn chế, tùy tên mục trên máy.
 * Cho phép sử dụng dữ liệu di động trong nền; kiểm tra quyền dùng dữ liệu khi bật chế độ tiết kiệm dữ liệu.
 * Bật thông báo của ứng dụng và các kênh tin nhắn/cuộc gọi cần dùng. Bật hiển thị trên màn hình khóa và biểu ngữ nổi nếu cần.
 * Kiểm tra cài đặt thông báo bên trong ứng dụng và từng cuộc trò chuyện.
 * Mở ứng dụng, vào đa nhiệm rồi khóa thẻ ứng dụng bằng tùy chọn ổ khóa.
 * Sau khi khởi động lại điện thoại, mở các ứng dụng cần nhận thông báo một lần.
 * Gửi thử tin nhắn mới vào từng tài khoản khi ứng dụng ở nền. Thử tiếp khi màn hình tắt, trên Wi-Fi và 4G/5G.
5. Hoàn tác theo bản sao lưu
 * Giữ file JSON cần dùng trong tools/backups; nếu đã chuyển backup ra ngoài, chép lại file trước khi chạy.
 * Kết nối đúng điện thoại đã tạo bản sao lưu.
 * Mở tools/CHAY_CONG_CU_FIX_THONG_BAO.bat, nhập 3.
 * Chọn số thứ tự của bản sao lưu cần dùng rồi nhấn Enter.
 * Chờ xử lý xong, chạy lại 1_KIEM_TRA_TRANG_THAI.bat và đối chiếu với bản sao lưu.
Để dùng ngay bản sao lưu mới nhất của điện thoại đang kết nối, chạy tools/3_KHOI_PHUC_HOAN_TAC.bat.
6. Kiểm tra kết nối Google
 * Kết nối điện thoại với máy tính.
 * Nhấp đúp tools/4_KIEM_TRA_KET_NOI_FCM.bat, hoặc chọn 4 trong menu chính.
 * Đọc trạng thái kết nối và các sự kiện có thời gian ghi nhận.
 * Khi kiểm tra lỗi mất thông báo, ghi lại giờ gửi tin, ứng dụng, bản gốc/nhân bản, loại mạng và trạng thái màn hình. Lấy kết quả trước khi mở lại ứng dụng đang lỗi.
7. Khi không tìm thấy điện thoại
 * Kiểm tra cáp, cổng USB, gỡ lỗi USB và yêu cầu cấp phép trên điện thoại.
 * Nếu đã chép ADB vào tools, mở PowerShell tại thư mục đó và chạy ./adb.exe devices. Nếu dùng ADB trong PATH, chạy adb devices.
 * Nếu trạng thái là unauthorized, mở khóa điện thoại và chọn Cho phép.
 * Nếu danh sách trống, đổi cáp/cổng USB và kiểm tra driver USB của điện thoại.
 * Nếu có nhiều thiết bị, ngắt các thiết bị còn lại rồi chạy lại công cụ.
8. Setting email
 * Mở ứng dụng Gmail, nhấn biểu tượng Menu (☰) ở góc trên bên trái, cuộn xuống chọn Cài đặt.
 * Chọn tài khoản Gmail cần nhận thông báo.
 * Kiểm tra mục Loại hộp thư đến.
 * Tại mục Thông báo, chọn Tất cả email (thay vì chỉ email có mức độ ưu tiên cao).
 * Nhấn vào Thông báo trong hộp thư đến:
   * Tích chọn Thông báo nhãn (chọn Đồng ý nếu có thông báo bật thông báo tài khoản).
   * Tích chọn Thông báo đối với mọi thư (để luôn rung/phát âm thanh khi có thư mới đến).
Ủng hộ ly cà phê ☕
Nếu công cụ hữu ích, bạn có thể ủng hộ mình một ly cà phê.
 * Ngân hàng: Techcombank
 * Số tài khoản: 31080688888888
Nhận code tool auto, MMO
Nhận viết các loại tool tự động hóa (auto) và tool MMO theo yêu cầu.
