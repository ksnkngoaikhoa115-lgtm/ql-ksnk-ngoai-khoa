export const TASK_EVALUATION_WARNING='Công việc chưa có đánh giá của quản lý. Vui lòng đánh giá trước khi chuyển sang ĐÃ HOÀN THÀNH.';
export function employeeCompleted(status:unknown){const value=String(status||'').trim().toUpperCase();return ['ĐÃ HOÀN THÀNH','HOÀN THÀNH','ĐÃ XONG','HOÀN TẤT'].includes(value);}
export function hasManagerEvaluation(value:unknown){return ['XUẤT SẮC','TỐT','KHÁ','TRUNG BÌNH','CHƯA ĐẠT','CHƯA ĐẠT_LÀM LẠI','CHƯA ĐẠT – LÀM LẠI','KÉM'].includes(String(value||'').trim().toUpperCase());}
export function requireManagerEvaluation(previous:unknown,status:unknown,evaluation:unknown){if(!employeeCompleted(previous)&&employeeCompleted(status)&&!hasManagerEvaluation(evaluation))throw new Error(TASK_EVALUATION_WARNING);}

/** A saved substantive management rating closes employee progress; redo remains actionable. */
export function evaluationCompletesTask(value:unknown){return ['XUẤT SẮC','TỐT','KHÁ','TRUNG BÌNH','KÉM'].includes(String(value||'').trim().toUpperCase());}

/** Effective display state; the underlying approved record remains untouched. */
export function effectiveTaskCompleted(data:Record<string,unknown>){const approval=String(data['Trạng thái phê duyệt']||data['Trạng thái xin ý kiến']||'').trim().toUpperCase();return approval==='ĐÃ PHÊ DUYỆT'||(!['TỪ CHỐI','YÊU CẦU BỔ SUNG'].includes(approval)&&evaluationCompletesTask(data['Đánh giá quản lý']||data['Đánh giá quản lý hiện tại']||data['Đánh giá']))||employeeCompleted(data['Trạng thái NV']||data['Trạng thái nhân viên']||data['Trạng thái']);}
