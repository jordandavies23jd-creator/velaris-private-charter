-- Apply after schema.sql. Existing delivery history is retained.
alter table public.bridge_enquiries add column revision integer not null default 0, add column current_handover uuid, add column followup_due_at timestamptz default (now()+interval '24 hours');
alter table public.bridge_deliveries add column revision integer not null default 0, add column superseded_at timestamptz, add column partner_decision text check(partner_decision in ('accepted','declined')), add column owner_name text, add column next_steps text, add column decision_at timestamptz;
alter table public.bridge_deliveries drop constraint bridge_deliveries_reference_kind_key, drop constraint bridge_deliveries_kind_check, drop constraint bridge_deliveries_status_check;
alter table public.bridge_deliveries add unique(reference,kind,revision), add check(kind in ('receipt','office','handover','customer_update','partner_followup')), add check(status in ('queued','sending','sent','failed','uncertain','cancelled'));
update public.bridge_enquiries e set current_handover=d.id from public.bridge_deliveries d where d.reference=e.reference and d.kind='handover';
create or replace function public.bridge_queue(p_ref text,p_partner uuid,p_subject text,p_body text,p_ack_hash text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare e bridge_enquiries; p bridge_partners; d bridge_deliveries;
begin
 select * into e from bridge_enquiries where reference=p_ref for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 select * into p from bridge_partners where id=p_partner for share;
 if not found or not p.active or not p.verified then raise exception 'PARTNER_NOT_APPROVED'; end if;
 if e.status in ('closed','withdrawn') then raise exception 'ENQUIRY_INACTIVE'; end if;
 if e.is_test<>p.is_test then raise exception 'TEST_LIVE_MISMATCH'; end if;
 if e.payload->>'sharing_permission'<>'accepted' or e.payload->>'sharing_permission' is null then raise exception 'SHARING_PERMISSION_REQUIRED'; end if;
 select * into d from bridge_deliveries where reference=p_ref and kind='handover' and revision=e.revision;
 if found then
  if d.partner_id<>p_partner then raise exception 'ALREADY_ROUTED'; end if;
  return to_jsonb(d);
 end if;
 insert into bridge_deliveries(reference,kind,partner_id,recipient,subject,body,ack_hash,revision)
 values(p_ref,'handover',p.id,p.email,p_subject,p_body,p_ack_hash,e.revision) returning * into d;
 update bridge_enquiries set status='handover_queued',current_handover=d.id,followup_due_at=now()+interval '24 hours',updated_at=now() where reference=p_ref;
 insert into bridge_events(reference,event,detail) values(p_ref,'handover_queued',jsonb_build_object('partner_id',p.id,'delivery_id',d.id));
 return to_jsonb(d);
end $$;

create or replace function public.bridge_claim(p_worker uuid,p_limit integer default 5)
returns setof public.bridge_deliveries language plpgsql security invoker set search_path=public as $$
begin
 -- A worker disappearing during a send is ambiguous. Never automatically resend it.
 with stale as (update bridge_deliveries set status='uncertain',last_error='Worker stopped before recording the send result. Check Gmail Sent before resolving.'
 where status='sending' and claimed_at<now()-interval '10 minutes' returning reference,id)
 insert into bridge_events(reference,event,detail) select reference,'delivery_uncertain',jsonb_build_object('delivery_id',id) from stale;
 return query with picked as (
 select d.id from bridge_deliveries d join bridge_enquiries e on e.reference=d.reference where d.status='queued' and d.superseded_at is null and e.status not in ('closed','withdrawn') and (d.partner_id is null or exists(select 1 from bridge_partners p where p.id=d.partner_id and p.active and p.verified)) order by d.created_at for update of d skip locked limit least(greatest(p_limit,1),10)
 ) update bridge_deliveries d set status='sending',claim_id=p_worker,claimed_at=now(),attempts=attempts+1
 from picked where d.id=picked.id returning d.*;
end $$;

create or replace function public.bridge_finish(p_id uuid,p_claim uuid,p_state text,p_message text default null,p_error text default null)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare d bridge_deliveries;
begin
 if p_state not in ('sent','failed','uncertain') then raise exception 'BAD_STATE'; end if;
 if p_state='sent' and coalesce(length(p_message),0)=0 then raise exception 'MESSAGE_ID_REQUIRED'; end if;
 select * into d from bridge_deliveries where id=p_id;
 if not found then raise exception 'NOT_FOUND'; end if;
 perform 1 from bridge_enquiries where reference=d.reference for update;
 update bridge_deliveries set status=p_state,gmail_message_id=p_message,last_error=left(p_error,500),sent_at=case when p_state='sent' then now() else null end
 where id=p_id and claim_id=p_claim and status='sending' returning * into d;
 if not found then raise exception 'CLAIM_MISMATCH'; end if;
 if d.kind='handover' then update bridge_enquiries set status=case when d.partner_decision='accepted' then 'partner_owned' when d.partner_decision='declined' then 'partner_declined' when d.acknowledged_at is not null then 'partner_acknowledged' when p_state='sent' then 'awaiting_partner_ack' else 'handover_'||p_state end,updated_at=now() where reference=d.reference and current_handover=d.id and status not in ('closed','withdrawn'); end if;
 insert into bridge_events(reference,event,detail) values(d.reference,'delivery_'||p_state,jsonb_build_object('delivery_id',d.id,'gmail_message_id',p_message));
 return to_jsonb(d);
end $$;

create or replace function public.bridge_ack(p_hash text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare d bridge_deliveries;
begin
 select * into d from bridge_deliveries where ack_hash=p_hash and kind='handover';
 if not found then raise exception 'INVALID_ACK'; end if;
 perform 1 from bridge_enquiries where reference=d.reference for update;
 select * into d from bridge_deliveries where ack_hash=p_hash and kind='handover' for update;
 if not found then raise exception 'INVALID_ACK'; end if;
 if d.superseded_at is not null or not exists(select 1 from bridge_enquiries where reference=d.reference and current_handover=d.id and status not in ('closed','withdrawn')) then raise exception 'ENQUIRY_INACTIVE'; end if;
 if d.status not in ('sending','sent','uncertain') then raise exception 'NOT_SENT'; end if;
 if d.acknowledged_at is null then
  update bridge_deliveries set acknowledged_at=now() where id=d.id;
  update bridge_enquiries set status=case when d.partner_decision='accepted' then 'partner_owned' when d.partner_decision='declined' then 'partner_declined' else 'partner_acknowledged' end,updated_at=now() where reference=d.reference;
  insert into bridge_events(reference,event,detail) values(d.reference,'partner_acknowledged',jsonb_build_object('delivery_id',d.id));
 end if;
 return jsonb_build_object('reference',d.reference,'acknowledged',true);
end $$;

create or replace function public.bridge_recover(p_id uuid,p_action text,p_message text default null)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare d bridge_deliveries;
begin
 select * into d from bridge_deliveries where id=p_id;
 if not found then raise exception 'NOT_FOUND'; end if;
 perform 1 from bridge_enquiries where reference=d.reference for update;
 select * into d from bridge_deliveries where id=p_id for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if d.superseded_at is not null or exists(select 1 from bridge_enquiries where reference=d.reference and status in ('closed','withdrawn')) then raise exception 'ENQUIRY_INACTIVE'; end if;
 if p_action='retry' then
  if d.status<>'failed' then raise exception 'RETRY_REQUIRES_CONFIRMED_FAILURE'; end if;
  update bridge_deliveries set status='queued',claim_id=null,claimed_at=null,last_error=null where id=p_id;
  if d.kind='handover' then update bridge_enquiries set status='handover_queued',updated_at=now() where reference=d.reference and current_handover=d.id and status not in ('closed','withdrawn'); end if;
 elsif p_action='confirm_not_sent' then
  if d.status<>'uncertain' or d.acknowledged_at is not null or coalesce(length(p_message),0)<20 then raise exception 'EVIDENCE_REQUIRED'; end if;
  update bridge_deliveries set status='failed',last_error='Office verified no send: '||left(p_message,400) where id=p_id;
  if d.kind='handover' then update bridge_enquiries set status='handover_failed',updated_at=now() where reference=d.reference and current_handover=d.id and status not in ('closed','withdrawn'); end if;
 elsif p_action='confirm_sent' then
  if d.status<>'uncertain' or coalesce(length(p_message),0)=0 then raise exception 'EVIDENCE_REQUIRED'; end if;
  update bridge_deliveries set status='sent',gmail_message_id=p_message,sent_at=now(),last_error=null where id=p_id;
  if d.kind='handover' then update bridge_enquiries set status=case when d.partner_decision='accepted' then 'partner_owned' when d.partner_decision='declined' then 'partner_declined' when d.acknowledged_at is null then 'awaiting_partner_ack' else 'partner_acknowledged' end where reference=d.reference and current_handover=d.id and status not in ('closed','withdrawn'); end if;
 else raise exception 'BAD_ACTION'; end if;
 insert into bridge_events(reference,event,detail) values(d.reference,'operator_'||p_action,jsonb_build_object('delivery_id',d.id,'gmail_message_id',p_message));
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.bridge_partner_response(p_hash text,p_decision text,p_owner text,p_steps text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare d bridge_deliveries; e bridge_enquiries; p bridge_partners; msg text;
begin
 select * into d from bridge_deliveries where ack_hash=p_hash and kind='handover';
 if not found then raise exception 'INVALID_ACK'; end if;
 select * into e from bridge_enquiries where reference=d.reference for update;
 select * into d from bridge_deliveries where id=d.id for update;
 select * into p from bridge_partners where id=d.partner_id for share;
 if e.current_handover<>d.id or d.superseded_at is not null or e.status in ('closed','withdrawn') then raise exception 'ENQUIRY_INACTIVE'; end if;
 if not p.active or not p.verified then raise exception 'PARTNER_NOT_APPROVED'; end if;
 if d.status not in ('sent','sending','uncertain') then raise exception 'NOT_SENT'; end if;
 if p_decision not in ('accepted','declined') or length(trim(p_owner)) not between 2 and 120 or length(trim(p_steps)) not between 10 and 2000 then raise exception 'RESPONSE_REQUIRED'; end if;
 if d.partner_decision is not null then
  if d.partner_decision<>p_decision or d.owner_name<>trim(p_owner) or d.next_steps<>trim(p_steps) then raise exception 'RESPONSE_ALREADY_RECORDED'; end if;
  return jsonb_build_object('reference',d.reference,'decision',d.partner_decision,'duplicate',true);
 end if;
 update bridge_deliveries set partner_decision=p_decision,owner_name=trim(p_owner),next_steps=trim(p_steps),decision_at=now(),acknowledged_at=coalesce(acknowledged_at,now()) where id=d.id;
 update bridge_enquiries set status=case when p_decision='accepted' then 'partner_owned' else 'partner_declined' end,followup_due_at=case when p_decision='accepted' then now()+interval '24 hours' else now() end,updated_at=now() where reference=e.reference;
 msg:=case when p_decision='accepted' then 'Your enquiry has been accepted for review by '||p.company||'. Your contact is '||trim(p_owner)||' ('||p.email||').'||E'\n\nNext steps from the charter team: '||trim(p_steps)||E'\n\nThis confirms responsibility for reviewing your enquiry, not yacht availability or a booking. Reply to Private Charter Office if you need help.' else 'The selected charter team cannot take this enquiry forward. Private Charter Office will review the next suitable option and contact you before proceeding.' end;
 insert into bridge_deliveries(reference,kind,recipient,subject,body,revision) values(e.reference,'customer_update',e.payload->>'email',case when e.is_test then 'TEST ONLY — ' else '' end||'Update on your charter enquiry — '||e.reference,msg,e.revision);
 insert into bridge_events(reference,event,detail) values(e.reference,'partner_'||p_decision,jsonb_build_object('delivery_id',d.id,'owner',trim(p_owner),'next_steps',trim(p_steps)));
 return jsonb_build_object('reference',e.reference,'decision',p_decision,'duplicate',false);
end $$;

create or replace function public.bridge_office(p_ref text,p_revision integer,p_action text,p_evidence text,p_payload jsonb default null,p_due timestamptz default null)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare e bridge_enquiries; d bridge_deliveries;
begin
 select * into e from bridge_enquiries where reference=p_ref for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if e.revision<>p_revision then raise exception 'STALE_REVISION'; end if;
 if length(trim(coalesce(p_evidence,''))) not between 20 and 2000 then raise exception 'EVIDENCE_REQUIRED'; end if;
 if p_action='note' then null;
 elsif p_action='deadline' then
  if p_due is null then raise exception 'DEADLINE_REQUIRED'; end if;
  update bridge_enquiries set followup_due_at=p_due,updated_at=now() where reference=p_ref;
 elsif p_action in ('correct','reassign','withdraw','close') then
  if e.status in ('closed','withdrawn') then raise exception 'ENQUIRY_INACTIVE'; end if;
  if exists(select 1 from bridge_deliveries where reference=p_ref and superseded_at is null and status in ('sending','uncertain')) then raise exception 'RESOLVE_SEND_FIRST'; end if;
  select * into d from bridge_deliveries where id=e.current_handover;
  if p_action='close' then
   if d.partner_decision is distinct from 'accepted' or not exists(select 1 from bridge_deliveries where reference=p_ref and kind='customer_update' and revision=e.revision and status='sent') then raise exception 'HANDOVER_NOT_COMPLETE'; end if;
   update bridge_enquiries set status='closed',followup_due_at=null,updated_at=now() where reference=p_ref;
  else
   if p_action='correct' and (p_payload is null or p_payload->>'email' is null) then raise exception 'INVALID_FIELD'; end if;
   update bridge_enquiries set payload=case when p_action='correct' then p_payload when p_action='withdraw' then jsonb_set(payload,'{sharing_permission}','"not_given"') else payload end,revision=revision+1,current_handover=null,status=case when p_action='withdraw' then 'withdrawn' else 'received' end,followup_due_at=case when p_action='withdraw' then null else now() end,updated_at=now() where reference=p_ref;
  end if;
  update bridge_deliveries set superseded_at=now(),status=case when status='queued' then 'cancelled' else status end where reference=p_ref and superseded_at is null and kind in ('handover','customer_update','partner_followup');
  -- Corrections must not send a receipt containing obsolete customer data.
  if p_action in ('correct','withdraw') then update bridge_deliveries set superseded_at=now(),status=case when status='queued' then 'cancelled' else status end where reference=p_ref and status in ('queued','failed'); end if;
 else raise exception 'BAD_ACTION'; end if;
 insert into bridge_events(reference,event,detail) values(p_ref,'office_'||p_action,jsonb_build_object('evidence',trim(p_evidence),'revision',e.revision,'previous_partner_delivery',e.current_handover));
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.bridge_followups()
returns integer language plpgsql security invoker set search_path=public as $$
declare n integer;
begin
 insert into bridge_deliveries(reference,kind,partner_id,recipient,subject,body,revision)
 select e.reference,'partner_followup',p.id,p.email,case when e.is_test then 'TEST ONLY — ' else '' end||'Follow-up — '||e.reference,
 'Please update Private Charter Office on enquiry '||e.reference||E'.\n\nPlease confirm who is handling this enquiry and the next step, or let us know if you cannot proceed. Reply to the original handover email. No availability or booking is assumed.',e.revision
 from bridge_enquiries e join bridge_deliveries d on d.id=e.current_handover join bridge_partners p on p.id=d.partner_id
 where e.followup_due_at<=now() and e.status in ('awaiting_partner_ack','partner_acknowledged','partner_owned') and d.status='sent' and d.superseded_at is null and p.active and p.verified
 on conflict(reference,kind,revision) do nothing;
 get diagnostics n=row_count;
 return n;
end $$;
revoke all on function public.bridge_partner_response(text,text,text,text),public.bridge_office(text,integer,text,text,jsonb,timestamptz),public.bridge_followups() from public,anon,authenticated;
grant execute on function public.bridge_partner_response(text,text,text,text),public.bridge_office(text,integer,text,text,jsonb,timestamptz),public.bridge_followups() to service_role;

create or replace function public.bridge_queue_checked(p_revision integer,p_ref text,p_partner uuid,p_subject text,p_body text,p_ack_hash text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare e bridge_enquiries;
begin
 select * into e from bridge_enquiries where reference=p_ref for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if p_revision is null or e.revision<>p_revision then raise exception 'STALE_REVISION'; end if;
 return bridge_queue(p_ref,p_partner,p_subject,p_body,p_ack_hash);
end $$;
revoke all on function public.bridge_queue_checked(integer,text,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.bridge_queue_checked(integer,text,uuid,text,text,text) to service_role;
