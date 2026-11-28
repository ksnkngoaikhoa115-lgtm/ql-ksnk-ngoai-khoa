-- Preserve the account UUID and its individual grants. A new management
-- appointment is reviewed in the existing administrator account form.
create or replace function public.nk_sync_hr_account_role() returns trigger
language plpgsql set search_path=public as $$
declare
 employee public.cx_people;
 position_name text;
 expected_role text;
 previous_role text;
begin
 if new.sheet_name <> 'DM_NHANVIEN' or public.cx_source_unit(new.data) is distinct from 'surgery' then return new; end if;
 for employee in select p.* from public.cx_people p
  join public.cx_staff_catalog s on s.code=p.staff_code and s.unit=p.unit
  where s.source_id=new.id and s.copies=1 and p.active and not p.admin
  for update of p loop
  position_name:=public.nk_approval_position(employee);
  expected_role:=case position_name when 'Trưởng khoa' then 'chief' when 'Điều dưỡng trưởng' then 'head_nurse'
   when 'Phó khoa' then 'deputy' when 'Tổ trưởng' then 'team' else 'staff' end;
  previous_role:=coalesce(employee.position_policy,case when employee.legacy_operator then 'chief'
   when employee.team_lead then 'team' else 'staff' end);
  if expected_role<>previous_role then
   update public.cx_people set position_policy=null,legacy_operator=false,team_lead=false,
    team_department=null,managed_departments='{}',can_approve_work=false,work_role_reviewed=false,
    version=gen_random_uuid() where id=employee.id;
  elsif expected_role='team' and employee.team_department is distinct from employee.department
   and public.cx_key(old.data->>'Bộ phận') is distinct from public.cx_key(new.data->>'Bộ phận')
   and public.cx_key(employee.team_department)=public.cx_key(old.data->>'Bộ phận') then
   update public.cx_people set team_department=employee.department,version=gen_random_uuid() where id=employee.id;
  end if;
 end loop;
 return new;
end $$;
revoke all on function public.nk_sync_hr_account_role() from public,anon,authenticated;
drop trigger if exists zz_nk_hr_account_role on public.ksnk_legacy_rows;
create trigger zz_nk_hr_account_role after update of data on public.ksnk_legacy_rows for each row
 when (new.sheet_name='DM_NHANVIEN' and (old.data->>'Chức vụ',old.data->>'Chức danh',old.data->>'Bộ phận') is distinct from (new.data->>'Chức vụ',new.data->>'Chức danh',new.data->>'Bộ phận'))
 execute function public.nk_sync_hr_account_role();
