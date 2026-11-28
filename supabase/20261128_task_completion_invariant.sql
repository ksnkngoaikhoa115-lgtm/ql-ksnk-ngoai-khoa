BEGIN;
CREATE FUNCTION public.nk_task_effective_completion(d jsonb) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO public AS $function$
 SELECT coalesce(upper(trim(coalesce(nullif(d->>'Trạng thái phê duyệt',''),d->>'Trạng thái xin ý kiến','')))='ĐÃ PHÊ DUYỆT'
 OR (upper(trim(coalesce(nullif(d->>'Trạng thái phê duyệt',''),d->>'Trạng thái xin ý kiến',''))) NOT IN ('TỪ CHỐI','YÊU CẦU BỔ SUNG')
 AND upper(trim(coalesce(nullif(d->>'Đánh giá quản lý',''),nullif(d->>'Đánh giá quản lý hiện tại',''),d->>'Đánh giá',''))) IN ('XUẤT SẮC','TỐT','KHÁ','TRUNG BÌNH','KÉM'))
 OR upper(trim(coalesce(nullif(d->>'Trạng thái NV',''),nullif(d->>'Trạng thái nhân viên',''),d->>'Trạng thái',''))) IN ('ĐÃ HOÀN THÀNH','HOÀN THÀNH','ĐÃ XONG','HOÀN TẤT'),false);
$function$;
CREATE FUNCTION public.nk_task_completion_on_write() RETURNS trigger LANGUAGE plpgsql SET search_path TO public AS $function$
BEGIN
 IF NEW.sheet_name<>'GIAO VIỆC' OR public.cx_source_unit(NEW.data) IS DISTINCT FROM 'surgery' THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' THEN
  -- Historical locked rows are never altered by this trigger.
  IF OLD.data->>'Trạng thái phê duyệt'='ĐÃ PHÊ DUYỆT' THEN RETURN NEW; END IF;
 END IF;
 IF public.nk_task_effective_completion(NEW.data) THEN NEW.data=NEW.data||jsonb_build_object('Trạng thái NV','ĐÃ HOÀN THÀNH'); END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER zz_nk_task_completion_on_write BEFORE INSERT OR UPDATE OF data ON public.ksnk_legacy_rows FOR EACH ROW EXECUTE FUNCTION public.nk_task_completion_on_write();
CREATE OR REPLACE FUNCTION public.cx_due(who uuid, scope text)
 RETURNS TABLE(kind text, quantity bigint)
 LANGUAGE sql
 STABLE
AS $function$
 select t.kind,count(*) from cx_threads t join cx_people a on a.id=who and a.active and a.unit='surgery' and t.units=array['surgery']
 where nk_work_scope(a,t) and (a.unit='company' or a.unit=any(t.units)) and (scope='all' or scope=any(t.units))
 and who=any(t.performers) and t.kind<>'chat' and t.status<>'Hoàn thành'
 and not (t.kind='task' and exists(select 1 from public.ksnk_legacy_rows r where r.id=t.source_row and r.sheet_name='GIAO VIỆC' and public.nk_task_effective_completion(r.data)))
 and t.due<=(now() at time zone 'Asia/Ho_Chi_Minh')::date group by t.kind
$function$
;
CREATE OR REPLACE FUNCTION public.nk_work_alerts(who uuid, filter_kind text, skip_rows integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
 with alerts as materialized (
 select t.id,t.kind,t.title,case when t.kind='task' and public.nk_task_effective_completion(r.data) then 'Hoàn thành' else t.status end as status,t.due,t.updated,t.performers,case when owner.admin and owner.staff_code is null then owner.username else owner.name end as sender,
 (now() at time zone 'Asia/Ho_Chi_Minh')::date as today,
 m.unread,m.preview,
 lower(coalesce(r.data->>'NHẮC HÀNG NGÀY',r.data->>'Nhắc hàng ngày','')) in ('có','true','1','x','yes') as daily
 from cx_threads t join cx_people a on a.id=who and a.active and a.unit='surgery'
 left join cx_people owner on owner.id=t.owner_id
 left join ksnk_legacy_rows r on r.id=t.source_row and t.kind in ('task','reminder')
 left join cx_reads seen on seen.thread=t.id and seen.person=who
 cross join lateral (
 select count(*) as unread,(array_agg(left(coalesce(nullif(body,''),'Ảnh / tài liệu'),180) order by seq desc))[1] as preview
 from cx_messages where (t.owner_id=who or who=any(t.performers||t.observers)) and thread=t.id and seq>coalesce(seen.seq,0) and sender is distinct from who
 ) m
 where t.units=array['surgery'] and t.kind in ('task','reminder')
 and nk_work_scope(a,t)
 ), eligible as (
 select * from alerts where unread>0 or (status<>'Hoàn thành' and
 (due<=today or (daily and due is null)))
 ), selected as (
 select * from eligible where filter_kind='all' or kind=filter_kind
 order by (due=today) desc nulls last,(unread>0) desc,updated desc,id
 limit 40 offset greatest(skip_rows,0)
 )
 select jsonb_build_object(
 'task',(select count(*) from eligible where kind='task'),
 'reminder',(select count(*) from eligible where kind='reminder'),
 'items',coalesce((select jsonb_agg(jsonb_build_object(
 'id',s.id,'kind',s.kind,'title',s.title,'status',s.status,'due',s.due,'sender',s.sender,
 'performers',(select string_agg(p.name,', ' order by u.ord) from unnest(s.performers) with ordinality u(id,ord) join cx_people p on p.id=u.id),
 'unread',s.unread,'preview',s.preview,'today',s.today,'daily',s.daily)
 order by (s.due=s.today) desc nulls last,(s.unread>0) desc,s.updated desc,s.id) from selected s),'[]'::jsonb))
$function$
;
COMMIT;
