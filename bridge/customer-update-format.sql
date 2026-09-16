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
 msg:=case when p_decision='accepted' then 'Your enquiry has been accepted for review by '||p.company||'. Your contact is '||trim(p_owner)||' ('||p.email||').'||chr(10)||chr(10)||'Next steps from the charter team: '||trim(p_steps)||chr(10)||chr(10)||'This confirms responsibility for reviewing your enquiry, not yacht availability or a booking. Reply to Private Charter Office if you need help.' else 'The selected charter team cannot take this enquiry forward. Private Charter Office will review the next suitable option and contact you before proceeding.' end;
 insert into bridge_deliveries(reference,kind,recipient,subject,body,revision) values(e.reference,'customer_update',e.payload->>'email',case when e.is_test then 'TEST ONLY — ' else '' end||'Update on your charter enquiry — '||e.reference,msg,e.revision);
 insert into bridge_events(reference,event,detail) values(e.reference,'partner_'||p_decision,jsonb_build_object('delivery_id',d.id,'owner',trim(p_owner),'next_steps',trim(p_steps)));
 return jsonb_build_object('reference',e.reference,'decision',p_decision,'duplicate',false);
end $$;

revoke all on function public.bridge_partner_response(text,text,text,text) from public,anon,authenticated;
grant execute on function public.bridge_partner_response(text,text,text,text) to service_role;
