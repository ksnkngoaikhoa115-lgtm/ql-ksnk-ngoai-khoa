BEGIN;
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
 if t.kind='task' and ((operation='approve' and new_state='ĐÃ PHÊ DUYỆT') or (operation in ('forward','consult') and evaluation in ('XUẤT SẮC','TỐT','KHÁ','TRUNG BÌNH','KÉM'))) then
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
