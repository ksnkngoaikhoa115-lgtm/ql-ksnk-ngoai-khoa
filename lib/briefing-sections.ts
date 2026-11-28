export const sectionTitles={
 overview:'Tổng quan trong kỳ',
 tasks:'Công việc và tiến độ',
 issues:'Tồn tại cần xử lý',
 errors:'Lỗi thường quy và vi phạm',
 content:'Ma trận theo tiêu chí',
 staff:'Ma trận theo nhân viên',
 opinions:'Ý kiến và kiến nghị',
 next:'Kế hoạch kỳ tới'
}
export type SectionKey=keyof typeof sectionTitles
export type Section={title:string;columns:string[];rows:(number|string|null)[][]}
