-- Active work must exist in the canonical KSNK source. Preserve orphan threads and message history.
CREATE OR REPLACE FUNCTION public.nk_work_scope(a cx_people, t cx_threads)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
select coalesce(a.active,false) and a.unit='surgery' and t.units=array['surgery'] and
(t.kind='chat' or (r.id is not null and r.sheet_name=case t.kind when 'task' then 'GIAO VIỆC' when 'reminder' then 'NHAC_VIEC_GHI_CHU' end and public.cx_source_unit(r.data)='surgery')) and
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
$function$;
