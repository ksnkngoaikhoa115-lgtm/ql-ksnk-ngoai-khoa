-- Multi-department deputy scope; existing accounts retain their single department.
BEGIN;
ALTER TABLE public.cx_people ADD COLUMN IF NOT EXISTS managed_departments text[];
ALTER TABLE public.cx_people ADD CONSTRAINT cx_people_managed_departments_limit CHECK (managed_departments IS NULL OR (cardinality(managed_departments)<=2 AND array_position(managed_departments,NULL) IS NULL));
CREATE OR REPLACE FUNCTION public.nk_managed_department_keys(p public.cx_people) RETURNS text[] LANGUAGE sql STABLE SET search_path TO 'public' AS $$
 SELECT ARRAY(SELECT DISTINCT public.cx_key(d) FROM unnest(CASE WHEN p.position_policy='deputy' AND p.team_lead AND p.work_role_reviewed AND cardinality(p.managed_departments) BETWEEN 1 AND 2 AND public.cx_key(p.managed_departments[1])=public.cx_key(p.team_department) THEN p.managed_departments ELSE ARRAY[coalesce(nullif(p.team_department,''),p.department)] END) d WHERE nullif(public.cx_key(d),'') IS NOT NULL)
$$;
REVOKE EXECUTE ON FUNCTION public.nk_managed_department_keys(public.cx_people) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nk_managed_department_keys(public.cx_people) TO service_role;
CREATE OR REPLACE FUNCTION public.nk_approval_eligible(p cx_people, t cx_threads, requester text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select coalesce(public.nk_approval_rank(public.nk_approval_position(p))>0
 and p.id::text<>coalesce(requester,'') and not(p.id=any(coalesce(t.performers,'{}'::uuid[])))
 and public.nk_work_scope(p,t)
 and (public.nk_approval_scope(p,case when t.kind='task' then 'tasks' else 'reminders' end)='hospital'
 or (public.nk_approval_scope(p,case when t.kind='task' then 'tasks' else 'reminders' end)='team'
 and cardinality(public.nk_managed_department_keys(p))>0
 and (nullif(public.cx_key(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận','')),'') is null
 or public.cx_key(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận',''))=any(public.nk_managed_department_keys(p)))
 and cardinality(coalesce(t.performers,'{}'::uuid[]))>0
 and not exists(select 1 from unnest(coalesce(t.performers,'{}'::uuid[])) q(id)
 left join public.cx_people person on person.id=q.id where person.id is null or person.unit is distinct from p.unit or not coalesce(public.cx_key(person.department)=any(public.nk_managed_department_keys(p)),false)))),false)
 from public.ksnk_legacy_rows r where r.id=t.source_row
$function$
;
CREATE OR REPLACE FUNCTION public.nk_checklist_evidence_access(who uuid, ref text, editing boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select count(*)=1 and coalesce(bool_and(cx_source_unit(r.data)='surgery' and a.active and a.unit='surgery'
   and a.team_lead and a.work_view and (not editing or a.work_edit)
   and cx_key(r.data->>'Bộ phận')=any(public.nk_managed_department_keys(a))),false)
 from ksnk_legacy_rows r cross join cx_people a
 where a.id=who and r.sheet_name='PHIEU_GIAMSAT'
 and coalesce(nullif(r.data->>'Mã phiếu',''),r.data->>'ID')=split_part(ref,':',1)
$function$
;
CREATE OR REPLACE FUNCTION public.nk_matrix_marks(who uuid, for_export boolean, after_row integer, page_size integer)
 RETURNS TABLE(row_no integer, form_id text, header jsonb, mark jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
with raw_scope as (
 select a.id,a.staff_code,public.nk_managed_department_keys(a) department_keys,
  case when a.admin then 'hospital'
       else coalesce(fp.grants #>> '{reports,view}',
         rd.grants #>> '{reports,view}',
         case when rp.scope in ('self','team','hospital') then rp.scope end,
         case when a.legacy_operator and a.work_view then 'hospital'
              when a.team_lead and a.work_role_reviewed and a.work_view then 'team'
              else 'self' end) end requested_view,
  case when a.admin then 'hospital'
       else coalesce(fp.grants #>> '{reports,export}',
         rd.grants #>> '{reports,export}',
         case when rp.can_export and rp.scope in ('self','team','hospital') then rp.scope end,
         case when a.legacy_operator and a.work_view then 'hospital'
              when a.team_lead and a.work_role_reviewed and a.work_view then 'team'
              else 'none' end) end requested_export
 from public.cx_people a
 left join public.nk_feature_permissions fp on fp.person=a.id
 left join public.nk_report_permissions rp on rp.person=a.id
 left join public.nk_role_permission_defaults rd on rd.role=case when a.position_policy='deputy' and a.team_lead and a.work_role_reviewed and a.work_view then 'deputy' when a.position_policy='head_nurse' and a.legacy_operator and a.work_role_reviewed and a.work_view then 'head_nurse'
    when a.legacy_operator and a.work_view then 'chief'
    when a.team_lead and a.work_role_reviewed and a.work_view then 'team'
    else 'staff' end
 where a.id=who and a.active and a.unit='surgery'
),
bounded as (
 select x.*,
  case when x.requested_view in ('none','self','team','hospital') then x.requested_view else 'none' end view_scope,
  case when x.requested_export in ('none','self','team','hospital') then x.requested_export else 'none' end export_scope
 from raw_scope x
),
access as (
 select b.*,
  case when for_export then (array['none','self','team','hospital']::text[])[least(
     array_position(array['none','self','team','hospital']::text[],b.export_scope),
     array_position(array['none','self','team','hospital']::text[],b.view_scope)
    )] else b.view_scope end permission_scope
 from bounded b
),
eligible as (
 select h.data,coalesce(nullif(h.data->>'Mã phiếu',''),h.data->>'ID') as id
 from access a
 join public.ksnk_legacy_rows h on h.sheet_name='PHIEU_GIAMSAT'
  and public.cx_source_unit(h.data)='surgery'
 where a.permission_scope<>'none'
 and (a.permission_scope='hospital'
  or (a.permission_scope='team' and public.cx_key(h.data->>'Bộ phận')=any(a.department_keys))
  or (a.permission_scope='self' and nullif(a.staff_code,'')=h.data->>'Mã NV'))
),
headers as (
 select id from eligible where nullif(id,'') is not null group by id having count(*)=1
)
select m.row_no,h.id,
 jsonb_build_object('date',coalesce(h.data->>'Ngày giám sát',h.data->>'Ngày'),
 'staffId',h.data->>'Mã NV','name',coalesce(h.data->>'Họ tên',h.data->>'Họ và tên'),
 'department',h.data->>'Bộ phận','area',h.data->>'Khu vực',
 'formCode',coalesce(h.data->>'Mã mẫu phiếu',h.id),
 'formName',h.data->>'Tên phiếu'),
 jsonb_build_object('criterionId',coalesce(m.data->>'Mã tiêu chí',m.data->>'ID'),
 'group',coalesce(m.data->>'Nhóm tiêu chí',m.data->>'Nhóm'),
 'content',coalesce(m.data->>'Nội dung tiêu chí',m.data->>'Nội dung'),
 'result',coalesce(m.data->>'Kết quả',m.data->>'Kết quả chấm'))
from public.ksnk_legacy_rows m
join headers ids on ids.id=coalesce(nullif(m.data->>'Mã phiếu',''),
 nullif(m.data->>'Mã phiếu giám sát',''),nullif(m.data->>'Form ID',''),m.legacy_id)
join eligible h on h.id=ids.id
where m.sheet_name='CT_PHIEU_GIAMSAT' and public.cx_source_unit(m.data)='surgery'
 and m.row_no>after_row
order by m.row_no
limit least(1000,greatest(page_size,1))
$function$
;
CREATE OR REPLACE FUNCTION public.nk_save_checklist(who uuid, rid uuid, header jsonb, marks jsonb, existing_row integer, expected_header jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare a cx_people; prev ksnk_legacy_rows; prevmarks jsonb; oldmark ksnk_legacy_rows;
 field jsonb; final_header jsonb; form_id text; next_no int; row_num int; result jsonb; known int[];
begin
 select * into a from cx_people where id=who and active and unit='surgery';
 if not found or not(a.admin or (a.legacy_operator or a.team_lead) and a.work_edit and a.work_view) then raise exception 'Thiếu quyền chấm phiếu';end if;
 if rid is null or jsonb_typeof(marks)<>'array' or jsonb_array_length(marks)=0 then raise exception 'Phiếu rỗng';end if;
 if not(a.admin or a.legacy_operator) then
  if cardinality(public.nk_managed_department_keys(a))=0 or not coalesce(cx_key(header->>'Bộ phận')=any(public.nk_managed_department_keys(a)),false)
  or not exists(select from ksnk_legacy_rows where sheet_name='DM_NHANVIEN' and cx_source_unit(data)='surgery' and nullif(data->>'Mã NV','')=header->>'Mã NV' and cx_key(data->>'Bộ phận')=cx_key(header->>'Bộ phận')) then raise exception 'Ngoài phạm vi bộ phận';end if;
 end if;
 perform pg_advisory_xact_lock(115,211126);
 select jsonb_build_object('id',v.form_id,'row_no',(v.header->>'row_no')::int) into result from nk_checklist_versions v where v.actor_id=who and v.request_id=rid;
 if found then return result;end if;
 if coalesce(existing_row,0)>0 then
  select * into prev from ksnk_legacy_rows where sheet_name='PHIEU_GIAMSAT' and row_no=existing_row and cx_source_unit(data)='surgery' for update;
  if not found or prev.data is distinct from expected_header then raise exception 'Phiếu vừa thay đổi. Tải lại trước khi lưu';end if;
  if not(a.admin or a.legacy_operator) and cx_key(prev.data->>'Bộ phận') is distinct from cx_key(header->>'Bộ phận') then raise exception 'Ngoài phạm vi bộ phận';end if;
  form_id=coalesce(nullif(prev.data->>'Mã phiếu',''),prev.data->>'ID');row_num=prev.row_no;
  if nullif(form_id,'') is null then raise exception 'Thiếu mã phiếu gốc';end if;
  select coalesce(jsonb_agg(to_jsonb(d) order by d.row_no),'[]'),array_agg(d.row_no order by d.row_no) into prevmarks,known
  from ksnk_legacy_rows d where d.sheet_name='CT_PHIEU_GIAMSAT' and cx_source_unit(d.data)='surgery' and coalesce(nullif(d.data->>'Mã phiếu',''),nullif(d.data->>'Mã phiếu giám sát',''),nullif(d.data->>'Form ID',''),d.legacy_id)=form_id;
  if coalesce(known,'{}'::int[]) is distinct from array(select (v->>'row_no')::int from jsonb_array_elements(marks) v order by (v->>'row_no')::int) then raise exception 'Danh sách lượt chấm đã thay đổi';end if;
 else
  form_id='PGS-'||rid::text;
  select coalesce(max(row_no),0)+1 into row_num from ksnk_legacy_rows where sheet_name='PHIEU_GIAMSAT';
 end if;
 final_header=coalesce(prev.data,'{}')||header||jsonb_build_object('Mã phiếu',form_id,'Thời gian lưu',now(),'Phiên bản phiếu',rid);
 if prev.id is null then insert into ksnk_legacy_rows(sheet_name,row_no,legacy_id,data) values('PHIEU_GIAMSAT',row_num,form_id,final_header);
 else update ksnk_legacy_rows set data=final_header where id=prev.id;end if;
 select coalesce(max(row_no),0)+1 into next_no from ksnk_legacy_rows where sheet_name='CT_PHIEU_GIAMSAT';
 for field in select * from jsonb_array_elements(marks) loop
  if (field->>'Kết quả') is null then raise exception 'Thiếu kết quả';end if;
  if prev.id is null then insert into ksnk_legacy_rows(sheet_name,row_no,legacy_id,data) values('CT_PHIEU_GIAMSAT',next_no,form_id,(field-'row_no')||jsonb_build_object('Mã phiếu',form_id));next_no=next_no+1;
  else update ksnk_legacy_rows set data=data||(field-'row_no')||jsonb_build_object('Mã phiếu',form_id) where sheet_name='CT_PHIEU_GIAMSAT' and row_no=(field->>'row_no')::int;end if;
 end loop;
 insert into nk_checklist_versions(form_id,actor_id,request_id,header,details,previous_header,previous_details) values(form_id,who,rid,jsonb_build_object('row_no',row_num,'data',final_header),marks,prev.data,prevmarks);
 return jsonb_build_object('id',form_id,'row_no',row_num);
end $function$
;
CREATE OR REPLACE FUNCTION public.nk_team_field(who uuid, row_id bigint, sheets text[], field_name text, previous text, new_value text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
begin
 update ksnk_legacy_rows r set data=r.data||jsonb_build_object(field_name,new_value)
 from cx_people a where a.id=who and a.active and a.unit='surgery' and a.work_view and a.work_edit
 and r.id=row_id and r.sheet_name=any(sheets) and cx_source_unit(r.data)='surgery' and (r.data->>field_name) is not distinct from previous
 and (a.legacy_operator or (a.team_lead and cardinality(public.nk_managed_department_keys(a))>0 and cx_key(r.data->>'Bộ phận')=any(public.nk_managed_department_keys(a))));
 return found;
end $function$
;
CREATE OR REPLACE FUNCTION public.nk_team_records(who uuid, sheets text[], fields text[], start_at integer)
 RETURNS TABLE(id bigint, sheet text, department text, fields_data jsonb)
 LANGUAGE sql
 STABLE
AS $function$
 select r.id,r.sheet_name,r.data->>'Bộ phận',coalesce((select jsonb_object_agg(k,v) from jsonb_each(r.data) as e(k,v) where k=any(fields)),'{}'::jsonb)
 from ksnk_legacy_rows r join cx_people a on a.id=who and a.active and a.unit='surgery' and a.work_view
 where r.sheet_name=any(sheets) and cx_source_unit(r.data)='surgery'
 and (a.legacy_operator or (a.team_lead and cardinality(public.nk_managed_department_keys(a))>0 and cx_key(r.data->>'Bộ phận')=any(public.nk_managed_department_keys(a))))
 order by r.id desc limit 50 offset greatest(start_at,0)
$function$
;
CREATE OR REPLACE FUNCTION public.nk_work_delete_allowed(a cx_people, t cx_threads)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select coalesce(a.active and a.unit='surgery' and t.units=array['surgery'] and
 t.kind in ('task','reminder') and public.nk_work_scope(a,t)
 and coalesce(r.data->>'Trạng thái phê duyệt','')<>'ĐÃ PHÊ DUYỆT'
 and case public.nk_work_feature_scope(a,case when t.kind='task' then 'tasks' else 'reminders' end,'delete')
 when 'hospital' then true
 when 'team' then (cardinality(public.nk_managed_department_keys(a))>0
 and (nullif(public.cx_key(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận','')),'') is null or public.cx_key(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận',''))=any(public.nk_managed_department_keys(a)))
 and cardinality(coalesce(t.performers,'{}'::uuid[]))>0
 and not exists(select 1 from unnest(coalesce(t.performers,'{}'::uuid[])) u(id)
 left join public.cx_people p on p.id=u.id where p.id is null or p.unit is distinct from a.unit or not coalesce(public.cx_key(p.department)=any(public.nk_managed_department_keys(a)),false)))
 or (t.kind='reminder' and (a.id=coalesce(t.source_creator_id,t.owner_id) or a.id=any(coalesce(t.performers,'{}'::uuid[]))))
 when 'self' then (a.id=coalesce(t.source_creator_id,t.owner_id) or (t.kind='reminder' and a.id=any(coalesce(t.performers,'{}'::uuid[]))))
 else false end,false)
 from public.ksnk_legacy_rows r where r.id=t.source_row and r.sheet_name=case when t.kind='task' then 'GIAO VIỆC' else 'NHAC_VIEC_GHI_CHU' end
$function$
;
CREATE OR REPLACE FUNCTION public.nk_work_scope(a cx_people, t cx_threads)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
select coalesce(a.active,false) and a.unit='surgery' and t.units=array['surgery'] and
(t.kind='chat' or public.nk_work_feature_scope(a,case when t.kind='task' then 'tasks' else 'reminders' end,'view')<>'none') and
case when t.kind='chat'
then a.id=t.owner_id or a.id=any(coalesce(t.performers,'{}'::uuid[])||coalesce(t.observers,'{}'::uuid[]))
else
 a.id=t.owner_id
 or a.id=any(coalesce(t.performers,'{}'::uuid[])||coalesce(t.observers,'{}'::uuid[]))
 or public.nk_work_feature_scope(a,case when t.kind='task' then 'tasks' else 'reminders' end,'view')='hospital'
 or (
   public.nk_work_feature_scope(a,case when t.kind='task' then 'tasks' else 'reminders' end,'view')='team'
   and cardinality(public.nk_managed_department_keys(a))>0
   and (
     case when nullif(trim(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận')), '') is not null
       then cx_key(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận'))=any(public.nk_managed_department_keys(a))
       else cardinality(coalesce(t.performers,'{}'::uuid[]))>0
        and not exists(
          select 1 from unnest(coalesce(t.performers,'{}'::uuid[])) u(id)
          left join cx_people p on p.id=u.id
          where p.id is null or p.unit is distinct from a.unit or
          not coalesce(cx_key(p.department)=any(public.nk_managed_department_keys(a)),false)
        )
     end
   )
 )
end
from (select 1) dummy left join public.ksnk_legacy_rows r on r.id=t.source_row
$function$
;
NOTIFY pgrst,'reload schema';
COMMIT;
