BEGIN;
CREATE OR REPLACE FUNCTION public.nk_work_decision(who uuid, work_id uuid, rid uuid, operation text, reviewer uuid, note text, expected text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare t cx_threads;a cx_people;mgr cx_people;r ksnk_legacy_rows;d jsonb;history jsonb;
 state text;new_state text;target uuid;targets uuid[];event jsonb;assigned text;
begin
 select * into t from cx_threads where id=work_id and kind in ('task','reminder') for update;
 if not found then return false;end if;
 select * into a from cx_people where id=who and active and unit='surgery';
 if not found or not nk_work_scope(a,t) or not(a.admin or a.work_edit or (operation='request' and coalesce(t.owner_id=who,false))) then return false;end if;
 select * into r from ksnk_legacy_rows where id=t.source_row and sheet_name=case when t.kind='task' then 'GIAO VIỆC' else 'NHAC_VIEC_GHI_CHU' end for update;
 if not found then return false;end if;
 d=r.data;
 state=coalesce(nullif(d->>'Trạng thái phê duyệt',''),case when t.kind='task' then 'CHƯA XIN Ý KIẾN' else 'KHÔNG YÊU CẦU' end);
 if exists(select from nk_work_events where thread=t.id and sender=a.id and request_id=rid) then return true; end if;
 if state is distinct from expected or length(note)>2000 or rid is null then return false;end if;
 assigned=d->>'Tài khoản duyệt';
 if operation='request' then
  if not (coalesce(who=t.owner_id,false) or coalesce(who=any(t.performers),false)) or state in ('CHỜ PHÊ DUYỆT','ĐÃ PHÊ DUYỆT') or nullif(trim(note),'') is null then return false;end if;
  select * into mgr from cx_people where id=reviewer and active and unit='surgery' and id<>who and (admin or (can_approve_work and work_edit and (team_lead or legacy_operator))) and nk_work_scope(cx_people,t);
  if not found then return false;end if;
  new_state='CHỜ PHÊ DUYỆT';targets=array[mgr.id];
  d=d||jsonb_build_object('Người xin duyệt ID',who,'Tài khoản duyệt',mgr.id,'Người quản lý phê duyệt',mgr.name,'Mã người quản lý',mgr.staff_code,'Nội dung xin phê duyệt',note,'Thời gian xin phê duyệt',now());
 else
  if who=t.owner_id or who=any(t.performers) and who::text=d->>'Người xin duyệt ID' then return false;end if;
  if (a.admin or (a.can_approve_work and (a.legacy_operator or (a.work_role_reviewed and a.team_lead)) and (assigned=a.id::text or (assigned is null and nullif(a.staff_code,'')=d->>'Mã người quản lý')))) is not true then return false;end if;
  if operation='reopen' then
   if state<>'ĐÃ PHÊ DUYỆT' or nullif(trim(note),'') is null then return false;end if;
   new_state='YÊU CẦU BỔ SUNG';
  else
   if state<>'CHỜ PHÊ DUYỆT' or operation not in ('approve','supplement','reject') then return false;end if;
   if operation<>'approve' and nullif(trim(note),'') is null then return false;end if;
   new_state=case operation when 'approve' then 'ĐÃ PHÊ DUYỆT' when 'supplement' then 'YÊU CẦU BỔ SUNG' else 'TỪ CHỐI' end;
  end if;
  targets=array_append(t.performers,t.owner_id);
  d=d||jsonb_build_object('Phản hồi quản lý',note,'Ngày phê duyệt',now());
 end if;
 history=coalesce(nullif(d->>'Lịch sử phê duyệt',''),'[]')::jsonb;
 if jsonb_typeof(history)<>'array' then raise exception 'Lịch sử phê duyệt không hợp lệ';end if;
 if t.kind='task' and operation='approve' and new_state='ĐÃ PHÊ DUYỆT' then
 d=d||jsonb_build_object('Trạng thái NV','ĐÃ HOÀN THÀNH');end if;
 event=jsonb_build_object('action',operation,'status',new_state,'at',now(),'actor',a.id,'managerName',a.name,'opinion',note,'requestId',rid);
 perform set_config('ksnk.reopening',case when operation='reopen' then t.id::text else '' end,true);
 update ksnk_legacy_rows set data=d||jsonb_build_object('Trạng thái phê duyệt',new_state,'Lịch sử phê duyệt',(history||jsonb_build_array(event))::text) where id=r.id;
 foreach target in array targets loop
  if target is not null then insert into nk_work_events(thread,sender,recipient,request_id,kind,body) values(t.id,a.id,target,rid,new_state,left(note,180)) on conflict do nothing;end if;
 end loop;
 update nk_work_events set handled_at=coalesce(handled_at,now()),read_at=coalesce(read_at,now()) where thread=t.id and recipient=a.id and request_id<>rid and handled_at is null;
 return true;
end $function$
;
CREATE OR REPLACE FUNCTION public.nk_work_decision_v2(who uuid, work_id uuid, rid uuid, operation text, reviewer uuid, note text, expected text, expected_revision integer, evaluation text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare t public.cx_threads;a public.cx_people;m public.cx_people;r public.ksnk_legacy_rows;d jsonb;h jsonb;ctx jsonb;prior jsonb;event jsonb;
 st text;new_state text;v int;target uuid;recipients uuid[];old_reviewer uuid;old_requester uuid;assigned uuid;label text;event_kind text;message text;
begin
 if rid is null or operation not in ('request','approve','forward','consult','supplement','reject','reopen') or note is null or length(note)>2000 then return false;end if;
 note=trim(note);
 select * into t from public.cx_threads where id=work_id and kind in ('task','reminder') for update;
 if not found then return false;end if;
 select * into a from public.cx_people where id=who and active and unit='surgery';
 if not found then return false;end if;
 select * into r from public.ksnk_legacy_rows where id=t.source_row and sheet_name=case when t.kind='task' then 'GIAO VIỆC' else 'NHAC_VIEC_GHI_CHU' end for update;
 if not found then return false;end if;
 ctx=public.nk_approval_context(who,work_id);
 if ctx is null then return false;end if;
 d=r.data;h=ctx->'history';st=ctx->>'status';v=(ctx->>'version')::int;
 select e into prior from jsonb_array_elements(h) e where e->>'requestId'=rid::text limit 1;
 if found then return coalesce(prior->>'actor'=who::text and prior->>'action'=operation and prior->>'opinion'=note and prior->>'inputReviewer'=coalesce(reviewer::text,'') and prior->>'evaluation'=coalesce(evaluation,''),false);end if;
 if st is distinct from expected or (ctx->>'revision')::int is distinct from expected_revision then return false;end if;
 select p.id into old_reviewer from public.cx_people p where p.id::text=d->>'Tài khoản duyệt';
 select p.id into old_requester from public.cx_people p where p.id::text=d->>'Người xin duyệt ID';
 if operation in ('request','forward','consult') then
 if note='' or reviewer is null or not exists(select 1 from jsonb_array_elements(ctx->'candidates') c where c->>'id'=reviewer::text) then return false;end if;
 if operation='request' and not (ctx->>'canSubmit')::boolean or operation<>'request' and not (ctx->>'canReview')::boolean then return false;end if;
 select * into m from public.cx_people where id=reviewer;
 assigned=reviewer;new_state='CHỜ PHÊ DUYỆT';
 d=d||jsonb_build_object('Người xin duyệt ID',who,'Tài khoản duyệt',assigned,'Người quản lý phê duyệt',m.name,'Mã người quản lý',m.staff_code,'Chức vụ phê duyệt',public.nk_approval_position(m),'Nội dung xin phê duyệt',note,'Thời gian xin phê duyệt',now(),'Phản hồi quản lý','','Ngày phê duyệt','');
 label=case operation when 'request' then 'XIN PHÊ DUYỆT' when 'forward' then 'ĐỒNG Ý VÀ TRÌNH CẤP TRÊN' else 'ĐÃ XEM XÉT VÀ XIN Ý KIẾN' end;
 else
 assigned=old_reviewer;
 if operation='reopen' then
 if not (ctx->>'canReopen')::boolean or note='' then return false;end if;
 new_state='YÊU CẦU BỔ SUNG';label='MỞ LẠI CÓ LÝ DO';v=v+1;
 else
 if not (ctx->>'canReview')::boolean then return false;end if;
 if operation in ('reject','supplement') and note='' then return false;end if;
 new_state=case operation when 'approve' then 'ĐÃ PHÊ DUYỆT' when 'supplement' then 'YÊU CẦU BỔ SUNG' else 'TỪ CHỐI' end;
 label=case operation when 'approve' then 'ĐÃ PHÊ DUYỆT' when 'supplement' then 'YÊU CẦU BỔ SUNG' else 'TỪ CHỐI PHÊ DUYỆT' end;
 end if;
 select * into m from public.cx_people where id=assigned;
 d=d||jsonb_build_object('Phản hồi quản lý',note,'Ngày phê duyệt',now());
 end if;
 if evaluation is not null then
 if operation not in ('approve','reject','supplement','forward','consult') or evaluation not in ('CHƯA BẮT ĐẦU','XUẤT SẮC','TỐT','KHÁ','CHƯA ĐẠT_LÀM LẠI','KÉM','QUÁ HẠN') then return false;end if;
 d=d||jsonb_build_object('Đánh giá quản lý',evaluation,'Đánh giá quản lý hiện tại',evaluation,'Người đánh giá hiện tại',a.name,'Thời gian đánh giá hiện tại',now());
 end if;
 if t.kind='task' and operation='approve' and new_state='ĐÃ PHÊ DUYỆT' then
 d=d||jsonb_build_object('Trạng thái NV','ĐÃ HOÀN THÀNH');end if;
 event=jsonb_build_object('action',operation,'status',new_state,'at',now(),'actor',who,'actorPosition',ctx->>'actorPosition','managerName',a.name,'reviewer',assigned,'reviewerPosition',public.nk_approval_position(m),'reviewerName',m.name,'opinion',note,'requestId',rid,'inputReviewer',coalesce(reviewer::text,''),'evaluation',coalesce(evaluation,''),'version',v);
 perform set_config('ksnk.reopening',t.id::text,true);
 update public.ksnk_legacy_rows set data=d||jsonb_build_object('Trạng thái phê duyệt',new_state,'Lịch sử phê duyệt',(h||jsonb_build_array(event))::text,'Phiên bản phê duyệt',v) where id=r.id;
 perform set_config('ksnk.reopening','',true);
 if old_reviewer is not null then
 update public.nk_work_events set handled_at=coalesce(handled_at,now()) where thread=t.id and recipient=old_reviewer and kind='CHỜ PHÊ DUYỆT' and handled_at is null;
 end if;
 recipients=case when operation='request' then array[assigned] else array_append(array_append(array_append(coalesce(t.performers,'{}'::uuid[]),coalesce(t.source_creator_id,t.owner_id)),old_requester),case when operation in ('forward','consult') then assigned else null end) end;
 for target in select distinct x from unnest(recipients) x where x is not null and x<>who loop
 if exists(select 1 from public.cx_people p where p.id=target and p.active and public.nk_work_scope(p,t)) then
 event_kind=case when new_state='CHỜ PHÊ DUYỆT' and target=assigned then 'CHỜ PHÊ DUYỆT' when operation in ('forward','consult') then label else new_state end;
 insert into public.nk_work_events(thread,sender,recipient,request_id,kind,body) values(t.id,who,target,rid,event_kind,left(note,180)) on conflict do nothing;
 end if;
 end loop;
 message=label||' · '||a.name||' — '||coalesce(ctx->>'actorPosition','')||case when operation in ('request','forward','consult') then E'\nĐến: '||m.name||' — '||coalesce(public.nk_approval_position(m),'') else '' end||E'\n'||note;
 perform public.cx_append(t.id,who,message,'[]'::jsonb,rid);
 return true;
end $function$
;
COMMIT;
