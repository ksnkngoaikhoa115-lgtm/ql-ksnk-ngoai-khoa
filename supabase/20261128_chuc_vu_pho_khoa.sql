-- Existing accounts keep their effective access until the administrator synchronizes the account.
alter table public.cx_people add column if not exists position_policy text
 check(position_policy in ('deputy','head_nurse'));
alter table public.nk_role_permission_defaults drop constraint nk_role_permission_defaults_role_check,
 add constraint nk_role_permission_defaults_role_check check(role in ('staff','team','chief','deputy','head_nurse'));
alter table public.nk_role_permission_history drop constraint nk_role_permission_history_role_check,
 add constraint nk_role_permission_history_role_check check(role in ('staff','team','chief','deputy','head_nurse'));

-- Keep the reviewed SQL policies, changing only the role lookup in each function.
do $migration$
declare entry record; source text; updated text;
begin
 for entry in select * from (values
 ('public.nk_set_role_permission_defaults(uuid,text,jsonb,uuid)','chosen_role not in (''staff'',''team'',''chief'')','chosen_role not in (''staff'',''team'',''chief'',''deputy'',''head_nurse'')'),
 ('public.nk_matrix_marks(uuid,boolean,integer,integer)','rd.role=case','rd.role=case when a.position_policy=''deputy'' and a.team_lead and a.work_role_reviewed and a.work_view then ''deputy'' when a.position_policy=''head_nurse'' and a.legacy_operator and a.work_role_reviewed and a.work_view then ''head_nurse'''),
 ('public.nk_work_feature_scope(public.cx_people,text,text)','select case when a.legacy_operator and a.work_view then ''chief''','select case when a.position_policy=''deputy'' and a.team_lead and a.work_role_reviewed and a.work_view then ''deputy'' when a.position_policy=''head_nurse'' and a.legacy_operator and a.work_role_reviewed and a.work_view then ''head_nurse'' when a.legacy_operator and a.work_view then ''chief'''),
 ('public.nk_approval_scope(public.cx_people,text)','rp.role=case','rp.role=case when p.position_policy=''deputy'' and p.team_lead and p.work_role_reviewed and p.work_view then ''deputy'' when p.position_policy=''head_nurse'' and p.legacy_operator and p.work_role_reviewed and p.work_view then ''head_nurse''')
 ) as changes(signature,old_text,new_text) loop
  source:=pg_get_functiondef(entry.signature::regprocedure);
  if strpos(source,entry.new_text)>0 then continue; end if;
  updated:=replace(source,entry.old_text,entry.new_text);
  if source=updated then raise exception 'Unexpected definition for %',entry.signature; end if;
  execute updated;
 end loop;
end $migration$;
insert into public.nk_role_permission_defaults(role,grants,changed_by)
 select 'head_nurse',grants,changed_by from public.nk_role_permission_defaults where role='chief'
 on conflict (role) do nothing;
insert into public.nk_role_permission_defaults(role,grants,changed_by)
 select 'deputy',grants,changed_by from public.nk_role_permission_defaults where role='team'
 on conflict (role) do nothing;
-- Map already reviewed accounts only where the baseline and the copied grants are identical.
update public.cx_people p set position_policy='head_nurse'
 where p.position_policy is null and p.unit='surgery' and p.work_role_reviewed and p.legacy_operator
 and public.nk_approval_position(p)='Điều dưỡng trưởng';
update public.cx_people p set position_policy='deputy'
 where p.position_policy is null and p.unit='surgery' and p.work_role_reviewed and p.team_lead and not p.legacy_operator
 and public.nk_approval_position(p)='Phó khoa';
notify pgrst,'reload schema';
