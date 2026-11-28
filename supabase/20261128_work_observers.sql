-- Cross-team observers are not performers and do not inherit work edit privileges.
create or replace function public.nk_observer_has_edit(who uuid,work_id uuid) returns boolean language sql stable set search_path to 'public' as $$
 select coalesce(public.nk_work_feature_scope(a,case t.kind when 'task' then 'tasks' else 'reminders' end,'edit')<>'none' and
 (a.id=t.owner_id or a.id=any(t.performers) or (public.nk_work_feature_scope(a,case t.kind when 'task' then 'tasks' else 'reminders' end,'edit') in ('team','hospital') and public.nk_work_scope(a,jsonb_populate_record(t,jsonb_build_object('observers','[]'::jsonb))))),false)
 from public.cx_threads t join public.cx_people a on a.id=who and a.active and a.unit='surgery' where t.id=work_id and t.kind in ('task','reminder')
$$;
revoke execute on function public.nk_observer_has_edit(uuid,uuid) from public,anon,authenticated;
grant execute on function public.nk_observer_has_edit(uuid,uuid) to service_role;
create or replace function public.nk_sync_work_observers() returns trigger language plpgsql set search_path to 'public' as $$
declare selected uuid[];
begin
 if not (new.data ? 'Người theo dõi ID') or (tg_op='UPDATE' and old.data->'Người theo dõi ID' is not distinct from new.data->'Người theo dõi ID') then return null;end if;
 if public.cx_source_unit(new.data) is distinct from 'surgery' then return null;end if;
 if jsonb_typeof(new.data->'Người theo dõi ID')<>'array' then raise exception 'Danh sách người theo dõi không hợp lệ';end if;
 select coalesce(array_agg(distinct p.id),'{}'::uuid[]) into selected from jsonb_array_elements_text(new.data->'Người theo dõi ID') x(id) join public.cx_people p on p.id::text=x.id and p.unit='surgery' and (p.active or p.pending_login);
 if cardinality(selected)<>jsonb_array_length(new.data->'Người theo dõi ID') then raise exception 'Người theo dõi không hợp lệ';end if;
 update public.cx_threads set observers=selected where source_row=new.id and kind in ('task','reminder') and units=array['surgery'];
 if not found then raise exception 'Không đồng bộ được người theo dõi';end if;
 return null;
end $$;
drop trigger if exists zzz_nk_sync_work_observers on public.ksnk_legacy_rows;
create trigger zzz_nk_sync_work_observers after insert or update of data on public.ksnk_legacy_rows for each row when (new.sheet_name in ('GIAO VIỆC','NHAC_VIEC_GHI_CHU')) execute function public.nk_sync_work_observers();
