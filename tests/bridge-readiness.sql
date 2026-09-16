begin;
do $$
declare
 ref text='PCO-TEST-READINESS-20260916';
 p jsonb='{"name":"Office rehearsal","email":"privatecharteroffice@gmail.com","area":"Greece","dates":"July 2027","guests":"8","budget":"GBP 100000","budget_scope":"Charter fee","sharing_permission":"not_given","service_acknowledgement":"accepted"}';
 partner uuid; d jsonb; repeated jsonb;
begin
 perform bridge_receive(ref,p,'readiness-test',ref,true,'Office-only rehearsal');
 insert into bridge_partners(company,email,territories,terms_evidence,verified,active,is_test)
 values('Readiness rehearsal','privatecharteroffice@gmail.com','Greece','Office-only rehearsal approval evidence.',true,true,true) returning id into partner;
 begin
  perform bridge_qualify(ref,0,'confirmed',false,'Office fixture','Confirmation evidence for the fixture.',now()+interval '1 day');
  raise exception 'confirmation should fail';
 exception when others then if SQLERRM not like '%CUSTOMER_CONFIRMATION_REQUIRED%' then raise; end if; end;
 perform bridge_qualify(ref,0,'confirmed',true,'Office fixture','Confirmation evidence for the fixture.',now()+interval '1 day');
 begin
  perform bridge_qualify(ref,0,'ready',true,'Office fixture','Confirmation evidence for the fixture.',now()+interval '1 day');
  raise exception 'permission should fail';
 exception when others then if SQLERRM not like '%SHARING_PERMISSION_REQUIRED%' then raise; end if; end;
 begin
  perform bridge_queue_ready(ref,partner,0,'Rehearsal','Rehearsal',repeat('a',64));
  raise exception 'unqualified route should fail';
 exception when others then if SQLERRM not like '%CUSTOMER_NOT_READY%' then raise; end if; end;
 update bridge_enquiries set payload=jsonb_set(jsonb_set(payload,'{sharing_permission}','"accepted"'),'{dates}','"July"') where reference=ref;
 begin
  perform bridge_qualify(ref,0,'ready',true,'Office fixture','Confirmation evidence for the fixture.',now()+interval '1 day');
  raise exception 'year should fail';
 exception when others then if SQLERRM not like '%DATES_YEAR_REQUIRED%' then raise; end if; end;
 update bridge_enquiries set payload=jsonb_set(payload,'{dates}','"July 2027"') where reference=ref;
 perform bridge_qualify(ref,0,'ready',true,'Office fixture','Confirmation evidence for the fixture.',now()+interval '1 day');
 d=bridge_queue_ready(ref,partner,0,'Rehearsal','Rehearsal',repeat('a',64));
 repeated=bridge_queue_ready(ref,partner,0,'Rehearsal','Rehearsal',repeat('b',64));
 if d->>'id' is distinct from repeated->>'id' then raise exception 'duplicate handover'; end if;
 perform bridge_office(ref,0,'correct','Office rehearsal changes the customer brief.',p||'{"sharing_permission":"accepted","dates":"August 2027"}'::jsonb,null);
 begin
  perform bridge_queue_ready(ref,partner,1,'Rehearsal','Rehearsal',repeat('c',64));
  raise exception 'stale qualification should fail';
 exception when others then if SQLERRM not like '%CUSTOMER_NOT_READY%' then raise; end if; end;
end $$;
rollback;
