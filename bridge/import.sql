-- Office-authenticated import, atomic with its source evidence and receipt queue.
create or replace function public.bridge_import(p_ref text,p_payload jsonb,p_fingerprint text,p_test boolean,p_receipt text,p_evidence text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare result jsonb;
begin
 if length(trim(coalesce(p_evidence,''))) not between 20 and 2000 then raise exception 'EVIDENCE_REQUIRED'; end if;
 if p_test and p_payload->>'email' is distinct from 'privatecharteroffice@gmail.com' then raise exception 'TEST_EMAIL_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_ref,0));
 if exists(select 1 from bridge_enquiries where reference=p_ref and is_test<>p_test) then raise exception 'TEST_LIVE_MISMATCH'; end if;
 result=bridge_receive(p_ref,p_payload,p_fingerprint,'office-import-'||p_ref,p_test,p_receipt);
 if not (result->>'duplicate')::boolean then
  insert into bridge_events(reference,event,detail) values(p_ref,'office_imported',jsonb_build_object('evidence',trim(p_evidence)));
 end if;
 return result;
end $$;
revoke all on function public.bridge_import(text,jsonb,text,boolean,text,text) from public,anon,authenticated;
grant execute on function public.bridge_import(text,jsonb,text,boolean,text,text) to service_role;
