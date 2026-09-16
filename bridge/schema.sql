-- Private Charter Office only. All access goes through the authenticated edge API.
create table public.bridge_operator_keys (key_hash text primary key, created_at timestamptz not null default now(), revoked_at timestamptz);
create table public.bridge_enquiries (
 reference text primary key, payload jsonb not null, fingerprint text not null,
 is_test boolean not null default false, status text not null default 'received',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.bridge_partners (
 id uuid primary key default gen_random_uuid(), company text not null, email text not null,
 territories text not null, minimum_budget_gbp numeric not null default 0,
 terms_evidence text not null, verified boolean not null default false,
 active boolean not null default false, is_test boolean not null default false,
 created_at timestamptz not null default now(),
 check(not active or (verified and length(terms_evidence)>10))
);
create table public.bridge_deliveries (
 id uuid primary key default gen_random_uuid(), reference text not null references public.bridge_enquiries(reference),
 kind text not null check(kind in ('receipt','office','handover')), partner_id uuid references public.bridge_partners(id),
 recipient text not null, subject text not null, body text not null,
 status text not null default 'queued' check(status in ('queued','sending','sent','failed','uncertain')),
 attempts integer not null default 0, claim_id uuid, claimed_at timestamptz,
 gmail_message_id text, last_error text, sent_at timestamptz,
 ack_hash text unique, acknowledged_at timestamptz,
 created_at timestamptz not null default now(), unique(reference,kind)
);
create table public.bridge_events (id bigint generated always as identity primary key, reference text not null references public.bridge_enquiries(reference), event text not null, detail jsonb not null default '{}', created_at timestamptz not null default now());
create table public.bridge_limits (bucket text primary key, hits integer not null, expires_at timestamptz not null);
create index bridge_delivery_queue on public.bridge_deliveries(status,created_at);
create index bridge_event_reference on public.bridge_events(reference,id);

alter table public.bridge_operator_keys enable row level security;
alter table public.bridge_enquiries enable row level security;
alter table public.bridge_partners enable row level security;
alter table public.bridge_deliveries enable row level security;
alter table public.bridge_events enable row level security;
alter table public.bridge_limits enable row level security;
revoke all on public.bridge_operator_keys, public.bridge_enquiries, public.bridge_partners, public.bridge_deliveries, public.bridge_events, public.bridge_limits from anon, authenticated;
grant all on public.bridge_operator_keys, public.bridge_enquiries, public.bridge_partners, public.bridge_deliveries, public.bridge_events, public.bridge_limits to service_role;
grant usage, select on sequence public.bridge_events_id_seq to service_role;

create function public.bridge_receive(p_ref text, p_payload jsonb, p_fingerprint text, p_bucket text, p_test boolean, p_receipt text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare old bridge_enquiries; n integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_ref,0));
 select * into old from bridge_enquiries where reference=p_ref;
 if found then
  if old.fingerprint <> p_fingerprint then raise exception 'REFERENCE_CONFLICT'; end if;
  return jsonb_build_object('reference',p_ref,'duplicate',true,'status',old.status);
 end if;
 insert into bridge_limits values(p_bucket,1,now()+interval '1 hour')
 on conflict(bucket) do update set hits=case when bridge_limits.expires_at<now() then 1 else bridge_limits.hits+1 end,
 expires_at=case when bridge_limits.expires_at<now() then now()+interval '1 hour' else bridge_limits.expires_at end returning hits into n;
 if n>10 then raise exception 'RATE_LIMIT'; end if;
 insert into bridge_enquiries(reference,payload,fingerprint,is_test) values(p_ref,p_payload,p_fingerprint,p_test);
 insert into bridge_deliveries(reference,kind,recipient,subject,body) values
 (p_ref,'receipt',p_payload->>'email',case when p_test then 'TEST ONLY — ' else '' end || 'Private Charter Office — '||p_ref,p_receipt),
 (p_ref,'office','privatecharteroffice@gmail.com',case when p_test then 'TEST ONLY — ' else '' end || 'New charter enquiry — '||p_ref,'Enquiry saved. Review it at https://velaris-private-charter.vercel.app/bridge/desk.html . Reference: '||p_ref);
 insert into bridge_events(reference,event) values(p_ref,'received');
 return jsonb_build_object('reference',p_ref,'duplicate',false,'status','received');
end $$;

create function public.bridge_queue(p_ref text,p_partner uuid,p_subject text,p_body text,p_ack_hash text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare e bridge_enquiries; p bridge_partners; d bridge_deliveries;
begin
 select * into e from bridge_enquiries where reference=p_ref for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 select * into p from bridge_partners where id=p_partner for share;
 if not found or not p.active or not p.verified then raise exception 'PARTNER_NOT_APPROVED'; end if;
 if e.is_test<>p.is_test then raise exception 'TEST_LIVE_MISMATCH'; end if;
 if e.payload->>'sharing_permission'<>'accepted' or e.payload->>'sharing_permission' is null then raise exception 'SHARING_PERMISSION_REQUIRED'; end if;
 select * into d from bridge_deliveries where reference=p_ref and kind='handover';
 if found then
  if d.partner_id<>p_partner then raise exception 'ALREADY_ROUTED'; end if;
  return to_jsonb(d);
 end if;
 insert into bridge_deliveries(reference,kind,partner_id,recipient,subject,body,ack_hash)
 values(p_ref,'handover',p.id,p.email,p_subject,p_body,p_ack_hash) returning * into d;
 update bridge_enquiries set status='handover_queued',updated_at=now() where reference=p_ref;
 insert into bridge_events(reference,event,detail) values(p_ref,'handover_queued',jsonb_build_object('partner_id',p.id,'delivery_id',d.id));
 return to_jsonb(d);
end $$;

create function public.bridge_claim(p_worker uuid,p_limit integer default 5)
returns setof public.bridge_deliveries language plpgsql security invoker set search_path=public as $$
begin
 -- A worker disappearing during a send is ambiguous. Never automatically resend it.
 with stale as (update bridge_deliveries set status='uncertain',last_error='Worker stopped before recording the send result. Check Gmail Sent before resolving.'
 where status='sending' and claimed_at<now()-interval '10 minutes' returning reference,id)
 insert into bridge_events(reference,event,detail) select reference,'delivery_uncertain',jsonb_build_object('delivery_id',id) from stale;
 return query with picked as (
 select id from bridge_deliveries where status='queued' order by created_at for update skip locked limit least(greatest(p_limit,1),10)
 ) update bridge_deliveries d set status='sending',claim_id=p_worker,claimed_at=now(),attempts=attempts+1
 from picked where d.id=picked.id returning d.*;
end $$;

create function public.bridge_finish(p_id uuid,p_claim uuid,p_state text,p_message text default null,p_error text default null)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare d bridge_deliveries;
begin
 if p_state not in ('sent','failed','uncertain') then raise exception 'BAD_STATE'; end if;
 if p_state='sent' and coalesce(length(p_message),0)=0 then raise exception 'MESSAGE_ID_REQUIRED'; end if;
 update bridge_deliveries set status=p_state,gmail_message_id=p_message,last_error=left(p_error,500),sent_at=case when p_state='sent' then now() else null end
 where id=p_id and claim_id=p_claim and status='sending' returning * into d;
 if not found then raise exception 'CLAIM_MISMATCH'; end if;
 if d.kind='handover' then update bridge_enquiries set status=case when d.acknowledged_at is not null then 'partner_acknowledged' when p_state='sent' then 'awaiting_partner_ack' else 'handover_'||p_state end,updated_at=now() where reference=d.reference; end if;
 insert into bridge_events(reference,event,detail) values(d.reference,'delivery_'||p_state,jsonb_build_object('delivery_id',d.id,'gmail_message_id',p_message));
 return to_jsonb(d);
end $$;

create function public.bridge_ack(p_hash text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare d bridge_deliveries;
begin
 select * into d from bridge_deliveries where ack_hash=p_hash and kind='handover' for update;
 if not found then raise exception 'INVALID_ACK'; end if;
 if d.status not in ('sending','sent','uncertain') then raise exception 'NOT_SENT'; end if;
 if d.acknowledged_at is null then
  update bridge_deliveries set acknowledged_at=now() where id=d.id;
  update bridge_enquiries set status='partner_acknowledged',updated_at=now() where reference=d.reference;
  insert into bridge_events(reference,event,detail) values(d.reference,'partner_acknowledged',jsonb_build_object('delivery_id',d.id));
 end if;
 return jsonb_build_object('reference',d.reference,'acknowledged',true);
end $$;

create function public.bridge_recover(p_id uuid,p_action text,p_message text default null)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare d bridge_deliveries;
begin
 select * into d from bridge_deliveries where id=p_id for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if p_action='retry' then
  if d.status<>'failed' then raise exception 'RETRY_REQUIRES_CONFIRMED_FAILURE'; end if;
  update bridge_deliveries set status='queued',claim_id=null,claimed_at=null,last_error=null where id=p_id;
  if d.kind='handover' then update bridge_enquiries set status='handover_queued',updated_at=now() where reference=d.reference; end if;
 elsif p_action='confirm_not_sent' then
  if d.status<>'uncertain' or d.acknowledged_at is not null or coalesce(length(p_message),0)<20 then raise exception 'EVIDENCE_REQUIRED'; end if;
  update bridge_deliveries set status='failed',last_error='Office verified no send: '||left(p_message,400) where id=p_id;
  if d.kind='handover' then update bridge_enquiries set status='handover_failed',updated_at=now() where reference=d.reference; end if;
 elsif p_action='confirm_sent' then
  if d.status<>'uncertain' or coalesce(length(p_message),0)=0 then raise exception 'EVIDENCE_REQUIRED'; end if;
  update bridge_deliveries set status='sent',gmail_message_id=p_message,sent_at=now(),last_error=null where id=p_id;
  if d.kind='handover' then update bridge_enquiries set status=case when d.acknowledged_at is null then 'awaiting_partner_ack' else 'partner_acknowledged' end where reference=d.reference; end if;
 else raise exception 'BAD_ACTION'; end if;
 insert into bridge_events(reference,event,detail) values(d.reference,'operator_'||p_action,jsonb_build_object('delivery_id',d.id,'gmail_message_id',p_message));
 return jsonb_build_object('ok',true);
end $$;

revoke all on function public.bridge_receive(text,jsonb,text,text,boolean,text),public.bridge_queue(text,uuid,text,text,text),public.bridge_claim(uuid,integer),public.bridge_finish(uuid,uuid,text,text,text),public.bridge_ack(text),public.bridge_recover(uuid,text,text) from public,anon,authenticated;
grant execute on function public.bridge_receive(text,jsonb,text,text,boolean,text),public.bridge_queue(text,uuid,text,text,text),public.bridge_claim(uuid,integer),public.bridge_finish(uuid,uuid,text,text,text),public.bridge_ack(text),public.bridge_recover(uuid,text,text) to service_role;
