-- Keep customer demand qualification separate from charter ownership.
alter table public.bridge_enquiries add column if not exists customer_readiness jsonb not null default '{}';
create or replace function public.bridge_qualify(p_ref text,p_revision integer,p_stage text,p_confirmed boolean,p_source text,p_evidence text,p_due timestamptz)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare e bridge_enquiries; q jsonb;
begin
 select * into e from bridge_enquiries where reference=p_ref for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if e.revision<>p_revision then raise exception 'STALE_REVISION'; end if;
 if e.status in ('closed','withdrawn') then raise exception 'ENQUIRY_INACTIVE'; end if;
 if p_stage is null or p_stage not in ('collecting','confirmed','ready') then raise exception 'BAD_ACTION'; end if;
 if length(trim(coalesce(p_evidence,''))) not between 20 and 2000 or length(trim(coalesce(p_source,''))) not between 1 and 180 then raise exception 'EVIDENCE_REQUIRED'; end if;
 if p_due is null or p_due<=now() then raise exception 'DEADLINE_REQUIRED'; end if;
 if p_stage in ('confirmed','ready') and p_confirmed is distinct from true then raise exception 'CUSTOMER_CONFIRMATION_REQUIRED'; end if;
 if p_stage='ready' then
  if e.payload->>'sharing_permission' is distinct from 'accepted' then raise exception 'SHARING_PERMISSION_REQUIRED'; end if;
  if coalesce(e.payload->>'dates','') !~ '\m20[0-9]{2}\M' then raise exception 'DATES_YEAR_REQUIRED'; end if;
 end if;
 q=jsonb_build_object('stage',p_stage,'revision',e.revision,'confirmed',p_confirmed is true,'source',trim(p_source),'evidence',trim(p_evidence),'reviewed_at',now());
 update bridge_enquiries set customer_readiness=q,followup_due_at=p_due,updated_at=now() where reference=p_ref;
 insert into bridge_events(reference,event,detail) values(p_ref,'customer_'||p_stage,jsonb_build_object('evidence',trim(p_evidence),'source',trim(p_source),'revision',e.revision));
 return jsonb_build_object('ok',true,'readiness',q);
end $$;
create or replace function public.bridge_queue_ready(p_ref text,p_partner uuid,p_revision integer,p_subject text,p_body text,p_ack_hash text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare e bridge_enquiries;
begin
 select * into e from bridge_enquiries where reference=p_ref for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if e.revision<>p_revision then raise exception 'STALE_REVISION'; end if;
 if e.customer_readiness->>'stage' is distinct from 'ready' or (e.customer_readiness->>'revision')::integer is distinct from e.revision then raise exception 'CUSTOMER_NOT_READY'; end if;
 return bridge_queue_checked(p_revision=>p_revision,p_ref=>p_ref,p_partner=>p_partner,p_subject=>p_subject,p_body=>p_body,p_ack_hash=>p_ack_hash);
end $$;
revoke all on function public.bridge_qualify(text,integer,text,boolean,text,text,timestamptz),public.bridge_queue_ready(text,uuid,integer,text,text,text) from public,anon,authenticated;
grant execute on function public.bridge_qualify(text,integer,text,boolean,text,text,timestamptz),public.bridge_queue_ready(text,uuid,integer,text,text,text) to service_role;
