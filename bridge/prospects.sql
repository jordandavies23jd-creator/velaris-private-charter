create table if not exists public.bridge_prospects (
 email text primary key check (length(email) between 5 and 254),
 company text not null,
 role text not null check(role in ('charter','referrer')),
 status text not null default 'awaiting_reply' check(status in ('awaiting_reply','qualifying','terms_pending','agreed','declined','bounced','paused')),
 evidence text not null default '',
 next_action text not null default '',
 followup_due_at timestamptz,
 gmail_thread_id text,
 last_sent_id text,
 updated_at timestamptz not null default now(),
 revision integer not null default 0,
 history jsonb not null default '[]'::jsonb
);
alter table public.bridge_prospects enable row level security;
revoke all on public.bridge_prospects from public,anon,authenticated;
grant all on public.bridge_prospects to service_role;
create or replace function public.bridge_prospect_update(p_email text,p_revision integer,p_status text,p_evidence text,p_action text,p_due timestamptz)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare old public.bridge_prospects; result public.bridge_prospects;
begin
 select * into old from bridge_prospects where email=p_email for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if old.revision<>p_revision then raise exception 'STALE_REVISION'; end if;
 if p_status not in ('awaiting_reply','qualifying','terms_pending','agreed','declined','bounced','paused') then raise exception 'INVALID_FIELD'; end if;
 if length(trim(p_evidence))<20 or length(p_evidence)>2000 or length(p_action)>1000 then raise exception 'EVIDENCE_REQUIRED'; end if;
 if p_status in ('awaiting_reply','qualifying','terms_pending') and (p_due is null or p_due<=now() or length(trim(p_action))<5) then raise exception 'DEADLINE_REQUIRED'; end if;
 update bridge_prospects set status=p_status,evidence=p_evidence,next_action=p_action,followup_due_at=p_due,
 revision=revision+1,updated_at=now(),history=history||jsonb_build_array(jsonb_build_object('at',now(),'previous_status',old.status,'status',p_status,'evidence',p_evidence,'action',p_action,'due',p_due))
 where email=p_email returning * into result;
 return to_jsonb(result);
end $$;
revoke all on function public.bridge_prospect_update(text,integer,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.bridge_prospect_update(text,integer,text,text,text,timestamptz) to service_role;
