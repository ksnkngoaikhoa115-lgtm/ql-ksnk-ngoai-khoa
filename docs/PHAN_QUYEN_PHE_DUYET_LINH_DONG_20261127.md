# Đặc tả phê duyệt đa cấp linh động — Giao việc & Nhắc việc
Ngày 27/11/2026 | Căn cứ phiên bản nguồn 512dbcd3fe419e9a74a5eaabfc7bc895bda13849.
Trạng thái: đặc tả triển khai, không phải xác nhận đã phát hành. Nhánh thiết kế được tách từ bản sao chưa đầy đủ; không deploy nhánh này.

## 1. Mục tiêu
Một biểu mẫu, một tác vụ, nhiều vòng phê duyệt tùy nhu cầu; không bắt buộc đi tuần tự. Người giao việc có thể duyệt việc do mình giao nếu đủ quyền và không phải chính người gửi yêu cầu. Người được giao việc hoặc quản lý đã duyệt ở vòng trước mặc định có quyền tiếp tục trình, không phụ thuộc người gửi lần đầu. Chỉ gửi một yêu cầu đang chờ tại một thời điểm.

## 2. Giao diện
Chỉ một nhãn “Chức vụ phê duyệt”. Các lựa chọn động: Người giao việc; Trưởng khoa; Phó khoa; Điều dưỡng trưởng; Tổ trưởng; chức vụ khác đã cấu hình. Ẩn lựa chọn không có người đủ điều kiện. Khi có đúng một tài khoản hợp lệ, tự chọn; nhiều tài khoản thì chọn họ tên theo ID, không so tên tự do. Hiển thị họ tên, chức vụ, bộ phận người nhận trước khi gửi. Không tự gửi khi đổi lựa chọn.
Lần đầu mặc định Người giao việc nếu đủ quyền, nếu không thì đề xuất quản lý trực tiếp hợp lệ và yêu cầu xác nhận; không tự chuyển sang người khác. Vòng tiếp theo ưu tiên người giao việc nếu chưa xử lý và đủ thẩm quyền đối với vòng đó, nếu không thì gợi ý cấp tiếp theo hợp lệ. Không có người đủ quyền: chặn gửi, thông báo quản trị viên.
Nội dung xin phê duyệt bắt buộc. Trong màn hình xử lý: Phê duyệt; Đồng ý và chuyển tiếp; Đã xem xét và xin ý kiến; Yêu cầu bổ sung; Từ chối. Chuyển tiếp sử dụng cùng nhãn Chức vụ phê duyệt. Sau khi đã duyệt, hiển thị nút Tiếp tục xin phê duyệt cho đối tượng có quyền. Giữ nguyên giao diện tác vụ và trao đổi song song.

## 3. Quyền và phạm vi
- Nhân viên: trình công việc được giao, tiếp tục trình ở vòng sau. Không tự duyệt.
- Tổ trưởng: duyệt trong tổ phụ trách, trình thẳng Trưởng khoa theo chỉ đạo, hoặc Điều dưỡng trưởng/Phó khoa nếu đủ quyền.
- Điều dưỡng trưởng: duyệt theo phạm vi được cấp, trình Trưởng khoa hoặc Phó khoa được phân công.
- Phó khoa: phạm vi toàn khoa hoặc các bộ phận được giao; không mặc định có quyền trên mọi nghiệp vụ của Điều dưỡng trưởng.
- Trưởng khoa: toàn khoa theo quyền thực tế; quyết định cuối cùng. Không bắt buộc có ý kiến trung gian.
- Người giao việc: được trình/duyệt khi có quyền tương ứng và đáp ứng điều kiện từng vòng.
- Người đã duyệt trước: được tiếp tục trình nếu còn hoạt động, còn quyền và phạm vi phù hợp. Không cần là người gửi ban đầu.
- Người đang được chỉ định duyệt: có quyền xử lý hoặc chuyển tiếp sau khi lưu ý kiến. Không mở rộng cho người chỉ quan sát.
- Quản trị viên: cấu hình quyền, chức vụ, phạm vi, ủy quyền có thời hạn; không tự động thay người duyệt chỉ vì có quyền admin.
Kiểm tra tài khoản hoạt động, liên kết nhân sự, quyền phê duyệt, ma trận phạm vi và quan hệ tác vụ ở server. Với tác vụ nhiều bộ phận, người duyệt cấp tổ phải có phạm vi bao phủ tác vụ cần duyệt; không tự mở quyền ngoài tổ. Chức vụ bỏ trống/đã nghỉ không xuất hiện. Vắng mặt: chỉ người được ủy quyền hợp lệ hoặc chuyển người duyệt có ghi lịch sử.

## 4. Trạng thái, vòng duyệt và dữ liệu
Tách trạng thái thực hiện công việc khỏi trạng thái phê duyệt. Trạng thái tổng hợp giữ tương thích: CHƯA XIN Ý KIẾN/KHÔNG YÊU CẦU, CHỜ PHÊ DUYỆT, ĐÃ PHÊ DUYỆT, YÊU CẦU BỔ SUNG, TỪ CHỐI. Hiển thị thêm tên/chức vụ người đang chờ, số vòng, cấp đã duyệt và lịch sử.
Mỗi vòng có ID riêng, người trình, người duyệt được chỉ định, snapshot chức vụ, nội dung, kết quả, ý kiến, thời điểm, phiên bản nội dung và requestId chống gửi trùng. Bảng lịch sử append-only; không ghi đè kết quả vòng trước. Chỉ một vòng pending trên mỗi tác vụ; khóa hàng hoặc ràng buộc duy nhất để chống đua dữ liệu. Chuyển tiếp đóng vòng hiện tại và mở vòng mới trong cùng transaction. Không tạo tác vụ mới.
Cho phép tiếp tục trình sau khi duyệt dù nội dung đã khóa; không coi việc trình tiếp là sửa nội dung. Nếu phải sửa nội dung nghiệp vụ sau duyệt, dùng luồng mở lại có quyền/lý do, tạo phiên bản mới, đánh dấu các duyệt trước là thuộc phiên bản cũ; không xóa. Phê duyệt cuối cùng là kết quả của vòng kết thúc hiện tại, có thể tiếp tục trình cấp có thẩm quyền nếu cần. Không tự động thay trạng thái hoàn thành công việc chỉ vì đã duyệt.
Chống tự duyệt (reviewer != requester) và xung đột lợi ích: không cho người thực hiện tự xác nhận kết quả công việc của chính mình. Chặn trình lại cùng người đã duyệt cùng phiên bản trừ vòng bổ sung hoặc mở lại có lý do. Chặn vòng lặp chuyển tiếp, không giới hạn cứng số cấp. Cấp chuyển tiếp phải được phép theo ma trận, có thể bỏ qua cấp trung gian. Sau yêu cầu bổ sung cho phép gửi lại người đã yêu cầu bổ sung nếu còn quyền; nếu không chọn người hợp lệ và ghi rõ lý do. Từ chối không tự động mở lại; cần hành động rõ ràng và quyền thích hợp.

## 5. Cấu hình
Danh mục chức vụ đồng bộ Nhân sự & Hợp đồng và Tài khoản. Cấu hình nhóm quyền, phạm vi, quyền duyệt kết thúc, quyền chuyển tiếp, chức vụ đích được phép, ủy quyền có thời hạn. Phó khoa phải được bổ sung vào chuẩn hóa chức vụ và ma trận, không suy ra quyền chỉ từ nhãn. Mặc định không bắt buộc nhiều cấp. Không cần sửa mã mỗi khi vị trí bỏ trống; quyền mới phải cấp rõ ràng. Bảo toàn dữ liệu cũ, không cấp quyền hàng loạt ngầm.

## 6. Thông báo/báo cáo
Gửi chuông và yêu cầu tới đúng người đang được chỉ định; khi chuyển tiếp đánh dấu yêu cầu cũ đã xử lý. Người giao việc, người thực hiện và người đã tham gia được xem lịch sử trong phạm vi được cấp; gửi thông báo kết quả phù hợp, không thông báo trùng. Cảnh báo chờ duyệt tắt khi vòng được xử lý, vòng mới tạo cảnh báo mới. Báo cáo lọc theo chức vụ, người duyệt, vòng, trạng thái và thời gian; một tác vụ chỉ đếm một lần trong tổng số tác vụ.

## 7. Triển khai kỹ thuật
Hoàn thành và kiểm tra đủ 180 tệp nguồn trên nhánh mirror trước khi tích hợp đặc tả này. Không ghi vào repo nguồn. Rà soát app/LegacyDashboard.tsx, app/api/connect/route.ts, app/api/modules/route.ts, public/connect/ui.js, lib/staff-roles.ts, lib/feature-permissions.ts, các màn hình ma trận và SQL nk_work_decision/nk_lock_approved_work/nk_my_work_events. Dùng API thống nhất cho quyết định duyệt; không để API cũ bỏ qua quy tắc mới. Cung cấp endpoint danh sách người duyệt theo tác vụ do server lọc. Kiểm tra lại quyền lúc submit và lúc duyệt. Giữ tương thích hồ sơ cũ; migration bổ sung, không xóa dữ liệu, không sửa ID người dùng. Tách thao tác tiếp tục trình khỏi thao tác mở khóa nội dung đã duyệt. Bản cài mới và nâng cấp tại chỗ phải có cùng chức năng. Chỉ áp dụng migration vào dự án đích rwasjtxvmqixgyaxiwhi sau kiểm thử, có phương án rollback tương thích; không thay đổi nguồn. Không đưa thông tin nhân sự/secret vào GitHub. Preview/kiểm thử trước Production Vercel ksnkngoaikhoa115-1474s-projects/ql-ksnk-ngoai-khoa.

## 8. Kiểm thử chấp nhận
1. Trưởng khoa giao Tổ trưởng, Tổ trưởng gửi thẳng Trưởng khoa, duyệt thành công.
2. Trưởng khoa giao Nhân viên trực tiếp, Nhân viên chọn Người giao việc, duyệt thành công.
3. Nhân viên chọn Tổ trưởng đúng tổ; Tổ trưởng duyệt, Nhân viên trình Trưởng khoa.
4. Tổ trưởng đã duyệt chủ động trình Điều dưỡng trưởng/Phó khoa/Trưởng khoa.
5. Điều dưỡng trưởng đã xem xét, trình thẳng Trưởng khoa; giữ ý kiến trước.
6. Không có Điều dưỡng trưởng; vẫn chọn được Trưởng khoa/Phó khoa hợp lệ.
7. Không có Phó khoa/Tổ trưởng; bỏ qua cấp trống, không lỗi.
8. Nhiều người cùng chức vụ: chọn đúng tài khoản, thông báo đúng người.
9. Người hết quyền, đã nghỉ, ngoài tổ, người quan sát, tự duyệt và admin không được chỉ định: bị chặn đúng.
10. Hai người trình đồng thời: chỉ một vòng pending, retry cùng requestId không sinh sự kiện trùng.
11. Chuyển tiếp sai cấp hoặc lặp người trên cùng phiên bản: bị chặn; bổ sung có lý do cho phép trình lại.
12. Đã duyệt vẫn trình thêm được mà không sửa nội dung khóa; lịch sử các vòng nguyên vẹn.
13. Yêu cầu bổ sung/từ chối, mở lại hợp lệ, thay người duyệt khi nghỉ việc có audit.
14. Tác vụ cũ, dữ liệu, báo cáo, chuông, chat, ma trận quyền không hồi quy.
15. Kiểm thử trên cả Giao việc và Nhắc việc; npm ci, typecheck, test, build; xác minh API health và kiểm thử vai trò trên preview trước phát hành.

## 9. Bổ sung bắt buộc — Từ chối phê duyệt và đồng bộ chức vụ
- Giữ đầy đủ lựa chọn Phê duyệt, Đồng ý và chuyển tiếp, Đã xem xét và xin ý kiến, Yêu cầu bổ sung, Từ chối phê duyệt ở từng vòng của Giao việc và Nhắc việc. Từ chối và yêu cầu bổ sung bắt buộc nhập lý do; từ chối kết thúc vòng với trạng thái TỪ CHỐI PHÊ DUYỆT màu đỏ, không xóa tác vụ hoặc lịch sử, không tự đổi trạng thái thực hiện, không tự chuyển cấp. Trình lại sau từ chối chỉ qua hành động được phân quyền, lý do và vòng mới có audit; không dùng chuyển cấp để lách từ chối.
- Đồng bộ chức vụ người giao việc, người thực hiện, người trình và người phê duyệt từ cùng danh mục Nhân sự & Hợp đồng/Tài khoản. Liên kết bằng ID tài khoản/nhân sự hoặc mã nhân viên duy nhất đã xác minh; không đoán theo tên, không nhập tay chức vụ trong tác vụ. Hiển thị Họ tên — Chức vụ — Bộ phận khi cần. Lựa chọn Người giao việc — [chức vụ] lấy đúng ID người giao gốc, không sửa ID để phù hợp lựa chọn duyệt. Kiểm tra quyền và phạm vi độc lập với chức vụ. Nếu thay đổi chức vụ hoặc nghỉ việc, danh sách hiện hành cập nhật; người mất quyền không được duyệt, việc chuyển người duyệt phải được phân công có ghi lý do. Giữ snapshot chức vụ, tên và ID tại thời điểm giao/trình/duyệt/từ chối; hồ sơ cũ thiếu snapshot không được suy diễn lịch sử. Thiếu hoặc trùng liên kết nhân sự: yêu cầu quản trị viên đối chiếu trước khi cho chọn duyệt.
- Kiểm thử: người giao trực tiếp duyệt/từ chối đúng ID; thay đổi chức vụ không ghi đè lịch sử hoặc tự cấp quyền; từ chối ở từng cấp và trình lại đúng quyền; trùng tên, thiếu mã, người giao nghỉ việc, chức vụ bỏ trống.

## 10. Liên thông phê duyệt với hệ thống tin nhắn CONNECT
### 10.1. Một luồng trao đổi trên mỗi tác vụ
- Giao việc và Nhắc việc tiếp tục dùng thread hiện có; không tạo cuộc trò chuyện riêng mỗi lần xin duyệt hay chuyển cấp. Bên trái biểu mẫu/chi tiết; bên phải cuộc trò chuyện. Mở từ tin nhắn, chuông, cảnh báo hoặc danh sách đều đến đúng tác vụ và vòng duyệt; giữ bố cục responsive.
- Mọi hành động nghiệp vụ (gửi xin duyệt, đồng ý, chuyển tiếp, xin ý kiến cấp trên, yêu cầu bổ sung, từ chối, tiếp tục trình, phân công lại, mở lại) tự tạo tin nhắn hệ thống có nhãn rõ, người thực hiện hành động, chức vụ snapshot, người nhận, nội dung/ý kiến, thời điểm, trạng thái và vòng. Tin nhắn có nút MỞ TÁC VỤ/PHÊ DUYỆT để tới biểu mẫu cùng tác vụ. Người có quyền chỉ thấy thao tác phù hợp; tin nhắn thường không thay thế quyết định phê duyệt.
- Tin nhắn hệ thống không cho sửa/xóa làm sai lịch sử; không trùng lặp khi retry. Mọi hành động duyệt thực hiện tại API/SQL có kiểm quyền và xác nhận; nút trong tin nhắn mở đúng màn hình chứ không tự duyệt. Tin nhắn, ảnh, tài liệu trao đổi dùng chức năng hiện có; không nhân bản tệp minh chứng theo vòng, quyền xem tệp kiểm tra theo tác vụ.

### 10.2. Định tuyến và thông báo
- Xin duyệt/chuyển cấp: chỉ tài khoản người duyệt đang được chỉ định nhận cảnh báo cần xử lý; người giao, người thực hiện, người trình và người đã duyệt liên quan có thể theo dõi lịch sử theo quyền, không gửi yêu cầu duyệt hàng loạt. Người duyệt mới được quyền truy cập đúng tác vụ và hội thoại trong phạm vi cần thiết sau kiểm tra quyền; không mở quyền toàn khoa/toàn tổ ngầm. Người duyệt cũ không giữ quyền duyệt vòng mới.
- Khi duyệt, yêu cầu bổ sung hoặc từ chối: gửi tin kết quả tới người thực hiện, người giao và người trình vòng đó, loại trùng người nhận và không gửi cảnh báo cho chính người thực hiện hành động. Khi chuyển tiếp, thông báo kết quả vòng cũ và yêu cầu vòng mới; không làm người duyệt cũ vẫn thấy yêu cầu chờ. Từ chối gửi đầy đủ lý do tới đối tượng có quyền; không gửi tới người không liên quan.
- Chuông thông báo và số tin chưa đọc đồng bộ với CONNECT; kiểm tra tin mới theo cơ chế hiện hành, mục tiêu cập nhật khoảng 5 giây nếu kết nối và trình duyệt cho phép. Tôn trọng bật/tắt âm thanh; không phát lại cùng sự kiện. Đọc tin chỉ đánh dấu đã đọc; không đồng nghĩa đã duyệt. Cảnh báo chờ duyệt chỉ hết khi yêu cầu được xử lý, chuyển cấp hoặc phân công lại hợp lệ. Không tạo hai chuông cho cùng một hành động từ hai nguồn sự kiện.
- Giữ lịch sử và các tin nhắn cũ. Thực hiện cập nhật vòng phê duyệt + sự kiện thông báo + tin nhắn hệ thống trong cùng giao dịch, hoặc dùng transactional outbox có cơ chế idempotency và retry; khóa duy nhất theo ID sự kiện/người nhận. Không ghi nhận thành công nếu thay đổi nghiệp vụ thất bại. Tách quyền đọc hội thoại, gửi tin, duyệt và xem báo cáo; không tin dữ liệu chức vụ hay người nhận do client tự gửi.

### 10.3. Kiểm thử bổ sung
- Nhân viên gửi Tổ trưởng, Tổ trưởng chuyển Trưởng khoa, Trưởng khoa duyệt/từ chối: đúng một thread, lịch sử đủ, chỉ người chờ duyệt nhận cảnh báo hành động, phản hồi đúng người.
- Mở từ chuông/tin nhắn trên máy tính và điện thoại: đúng tác vụ/vòng; đọc tin không làm hết chờ duyệt; xử lý vòng cũ hết cảnh báo, vòng mới xuất hiện đúng người.
- Retry/mất mạng/hai lần bấm: không phát sinh tin hoặc chuông trùng; giao dịch thất bại không có tin giả thành công. Kiểm tra người ngoài phạm vi không đọc được tin hoặc tệp; người bị thu quyền không duyệt được từ tin cũ.
- Kiểm tra đồng thời Giao việc, Nhắc việc, CONNECT, cảnh báo trang chủ, báo cáo và ma trận quyền; dữ liệu hiện hữu nguyên vẹn.
