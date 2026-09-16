begin;
do $$ declare p jsonb='{"email":"privatecharteroffice@gmail.com","sharing_permission":"not_given"}'; r jsonb;
begin
 r=bridge_import('PCO-TEST-IMPORT-20260916',p,'import-test',true,'Office-only import rehearsal','Office rehearsal: original message and consent reviewed.');
 if (r->>'duplicate')::boolean then raise exception 'expected first import'; end if;
 r=bridge_import('PCO-TEST-IMPORT-20260916',p,'import-test',true,'Office-only import rehearsal','Office rehearsal: original message and consent reviewed.');
 if not (r->>'duplicate')::boolean then raise exception 'expected duplicate'; end if;
 if (select count(*) from bridge_events where reference='PCO-TEST-IMPORT-20260916' and event='office_imported')<>1 then raise exception 'duplicate event'; end if;
 if (select count(*) from bridge_deliveries where reference='PCO-TEST-IMPORT-20260916')<>2 then raise exception 'duplicate receipt'; end if;
 begin perform bridge_import('PCO-TEST-IMPORT-20260916',p,'different',true,'receipt','Office rehearsal evidence with sufficient length.'); raise exception 'conflict should fail'; exception when others then if SQLERRM not like '%REFERENCE_CONFLICT%' then raise; end if; end;
 begin perform bridge_import('PCO-TEST-IMPORT-20260916',p,'import-test',false,'receipt','Office rehearsal evidence with sufficient length.'); raise exception 'test mismatch should fail'; exception when others then if SQLERRM not like '%TEST_LIVE_MISMATCH%' then raise; end if; end;
 begin perform bridge_import('PCO-TEST-IMPORT-BAD',p,'test',true,'receipt','short'); raise exception 'evidence should fail'; exception when others then if SQLERRM not like '%EVIDENCE_REQUIRED%' then raise; end if; end;
end $$;
rollback;
