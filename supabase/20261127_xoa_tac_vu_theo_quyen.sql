begin;
create or replace function public.nk_work_feature_scope(a public.cx_people,feature text,action text)
returns text language sql stable set search_path=public as $$
with role_name as (
 select case when a.legacy_operator and a.work_view then 'chief'
             when a.team_lead and a.work_role_reviewed and a.work_view then 'team'
             else 'staff' end r
), permissions as (
 select coalesce(case when a.admin then 'hospital' end,
   fp.grants #>> array[feature,action],
   rp.grants #>> array[feature,action],
   case when action='view' or action='history' or action='edit' then
    case when a.legacy_operator and a.work_view then 'hospital'
         when a.team_lead and a.work_role_reviewed and a.work_view then 'team'
         when action='edit' then 'self' else 'self' end
   when action in ('create','delete') then
    case when a.legacy_operator and a.work_view and a.work_edit then 'hospital'
         when a.team_lead and a.work_role_reviewed and a.work_view and a.work_edit then 'team'
         when action='delete' and feature='reminders' and not (a.legacy_operator or a.team_lead) then 'self'
         else 'none' end else 'none' end) as requested,
 coalesce(case when a.admin then 'hospital' end,
   fp.grants #>> array[feature,'view'],
   rp.grants #>> array[feature,'view'],
   case when a.legacy_operator and a.work_view then 'hospital'
        when a.team_lead and a.work_role_reviewed and a.work_view then 'team'
        else 'self' end) as view_scope
 from role_name role
 left join public.nk_feature_permissions fp on fp.person=a.id
 left join public.nk_role_permission_defaults rp on rp.role=role.r
)
select case when requested not in ('none','self','team','hospital') then 'none'
            when requested='none' then 'none'
            when action='view' then requested
            when view_scope not in ('none','self','team','hospital') then 'none'
            when array_position(array['none','self','team','hospital'],requested)
              >array_position(array['none','self','team','hospital'],view_scope) then view_scope
            else requested end
from permissions
$$;
revoke all on function public.nk_work_feature_scope(public.cx_people,text,text) from public,anon,authenticated;
grant execute on function public.nk_work_feature_scope(public.cx_people,text,text) to service_role;


-- Private archive, retaining the source and thread snapshot before any deletion.
create table if not exists public.nk_deleted_work_archive(
 source_id bigint primary key, thread_id uuid not null, kind text not null,
 deleted_by uuid not null, deleted_at timestamptz not null default now(),
 source_snapshot jsonb not null, thread_snapshot jsonb not null
);
alter table public.nk_deleted_work_archive enable row level security;
revoke all on public.nk_deleted_work_archive from public,anon,authenticated;
grant select,insert on public.nk_deleted_work_archive to service_role;
create or replace function public.nk_work_delete_allowed(a public.cx_people,t public.cx_threads)
returns boolean language sql stable set search_path=public as $$
 select coalesce(a.active and a.unit='surgery' and t.units=array['surgery'] and
 t.kind in ('task','reminder') and public.nk_work_scope(a,t)
 and coalesce(r.data->>'Trạng thái phê duyệt','')<>'ĐÃ PHÊ DUYỆT'
 and case public.nk_work_feature_scope(a,case when t.kind='task' then 'tasks' else 'reminders' end,'delete')
 when 'hospital' then true
 when 'team' then (nullif(public.cx_key(coalesce(nullif(a.team_department,''),a.department)),'') is not null
 and (nullif(public.cx_key(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận','')),'') is null or public.cx_key(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận',''))=public.cx_key(coalesce(nullif(a.team_department,''),a.department)))
 and cardinality(coalesce(t.performers,'{}'::uuid[]))>0
 and not exists(select 1 from unnest(coalesce(t.performers,'{}'::uuid[])) u(id)
 left join public.cx_people p on p.id=u.id where p.id is null or p.unit is distinct from a.unit or public.cx_key(p.department) is distinct from public.cx_key(coalesce(nullif(a.team_department,''),a.department))))
 or (t.kind='reminder' and (a.id=coalesce(t.source_creator_id,t.owner_id) or a.id=any(coalesce(t.performers,'{}'::uuid[]))))
 when 'self' then (a.id=coalesce(t.source_creator_id,t.owner_id) or (t.kind='reminder' and a.id=any(coalesce(t.performers,'{}'::uuid[]))))
 else false end,false)
 from public.ksnk_legacy_rows r where r.id=t.source_row and r.sheet_name=case when t.kind='task' then 'GIAO VIỆC' else 'NHAC_VIEC_GHI_CHU' end
$$;
create or replace function public.nk_work_delete_options(who uuid,source_ids bigint[])
returns table(source_id bigint,can_delete boolean) language sql stable set search_path=public as $$
 select t.source_row::bigint,coalesce(public.nk_work_delete_allowed(a,t),false)
 from public.cx_threads t join public.cx_people a on a.id=who
 where t.source_row=any(source_ids) and t.kind in ('task','reminder') and public.nk_work_scope(a,t)
$$;
create or replace function public.nk_work_delete_v2(who uuid,work_id uuid)
returns boolean language plpgsql set search_path=public as $$
declare t public.cx_threads;a public.cx_people;r public.ksnk_legacy_rows;
begin
 select * into t from public.cx_threads where id=work_id and kind in ('task','reminder') for update;
 if not found then return false;end if;
 select * into a from public.cx_people where id=who and active and unit='surgery';
 if not found then return false;end if;
 select * into r from public.ksnk_legacy_rows where id=t.source_row for update;
 if not found or not coalesce(public.nk_work_delete_allowed(a,t),false) then return false;end if;
 insert into public.nk_deleted_work_archive(source_id,thread_id,kind,deleted_by,source_snapshot,thread_snapshot)
 values(r.id,t.id,t.kind,who,to_jsonb(r),to_jsonb(t));
 update public.nk_work_events set handled_at=coalesce(handled_at,now()),read_at=coalesce(read_at,now()) where thread=t.id;
 delete from public.ksnk_legacy_rows where id=r.id;
 return true;
end $$;
revoke all on function public.nk_work_delete_allowed(public.cx_people,public.cx_threads),public.nk_work_delete_options(uuid,bigint[]),public.nk_work_delete_v2(uuid,uuid) from public,anon,authenticated;
grant execute on function public.nk_work_delete_allowed(public.cx_people,public.cx_threads),public.nk_work_delete_options(uuid,bigint[]),public.nk_work_delete_v2(uuid,uuid) to service_role;
commit;
