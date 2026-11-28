begin;
-- Normalize only HR labels; preserve the original identity/code comparison function.
create or replace function public.nk_approval_position(p public.cx_people)
returns text language sql stable set search_path=public as $$
 select case translate(regexp_replace(normalize(public.cx_key(coalesce(nullif(r.data->>'Chức vụ',''),r.data->>'Chức danh','')),NFD),U&'[\0300-\036f]','','g'),'đ','d')
 when 'truong khoa' then 'Trưởng khoa' when 'pho khoa' then 'Phó khoa'
 when 'dieu duong truong' then 'Điều dưỡng trưởng' when 'dd truong' then 'Điều dưỡng trưởng'
 when 'to truong' then 'Tổ trưởng' when 'to truong bo phan' then 'Tổ trưởng'
 when 'nhan vien' then 'Nhân viên' when 'nv' then 'Nhân viên'
 when 'ho ly' then 'Nhân viên' when 'xu ly dung cu' then 'Nhân viên'
 when 'nhan vien xu ly dung cu' then 'Nhân viên' when 'nhan vien giam sat' then 'Nhân viên'
 when 'nhan vien giat la' then 'Nhân viên' when 'giam sat' then 'Nhân viên'
 when 'giat la' then 'Nhân viên' when 'dung cu' then 'Nhân viên'
 when 'nv dung cu' then 'Nhân viên' when 'nhan vien dung cu' then 'Nhân viên'
 when 'ky thuat vien' then 'Nhân viên' when 'ktv' then 'Nhân viên' end
 from public.cx_staff_catalog s join public.ksnk_legacy_rows r on r.id=s.source_id
 where p.active and p.unit='surgery' and nullif(p.staff_code,'') is not null
 and s.unit=p.unit and s.code=public.cx_key(p.staff_code) and s.copies=1
 and translate(regexp_replace(normalize(public.cx_key(coalesce(r.data->>'Trạng thái','')),NFD),U&'[\0300-\036f]','','g'),'đ','d') in ('','dang lam viec','dang lam','lam viec','hoat dong')
$$;
revoke all on function public.nk_approval_position(public.cx_people) from public,anon,authenticated;
grant execute on function public.nk_approval_position(public.cx_people) to service_role;
commit;
