import { EMAIL, validateIntake, handoverBody, receiptBody } from './core.js';
const dbUrl = Deno.env.get('SUPABASE_URL')!;
const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const origins = new Set(['https://velaris-private-charter.vercel.app','http://127.0.0.1:8090']);
async function hash(s: string) { return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))),x=>x.toString(16).padStart(2,'0')).join(''); }
async function db(path: string, method='GET', body?: unknown) {
  const response = await fetch(dbUrl+'/rest/v1/'+path,{method,headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json',Prefer:'return=representation'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
  const data = await response.json();
  if (!response.ok) throw new Error(data.message || 'DATABASE_UNAVAILABLE');
  return data;
}
const rpc=(name:string,args:unknown)=>db('rpc/'+name,'POST',args);
async function allRows(path:string) {
  const rows=[];
  for(let offset=0;offset<10000;offset+=500){const page=await db(path+'&limit=500&offset='+offset);rows.push(...page);if(page.length<500)return rows;}
  throw new Error('HISTORY_LIMIT');
}
async function operator(req:Request) {
  const key=req.headers.get('Authorization')?.replace(/^Bearer /,'') || '';
  if(key.length<40 || key.length>200) return false;
  return (await db('bridge_operator_keys?key_hash=eq.'+await hash(key)+'&revoked_at=is.null&select=key_hash')).length===1;
}
Deno.serve(async req => {
  const origin=req.headers.get('Origin') || '';
  const cors={ 'Access-Control-Allow-Origin':origins.has(origin)?origin:'https://velaris-private-charter.vercel.app', 'Access-Control-Allow-Headers':'authorization,apikey,content-type', 'Access-Control-Allow-Methods':'POST,OPTIONS', 'Vary':'Origin','Cache-Control':'no-store','Content-Type':'application/json' };
  const respond=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:cors});
  if(req.method==='OPTIONS')return respond({ok:true});
  if(req.method!=='POST')return respond({error:'METHOD_NOT_ALLOWED'},405);
  if(origin && !origins.has(origin))return respond({error:'ORIGIN_NOT_ALLOWED'},403);
  try {
    const raw=await req.text(); if(raw.length>16000)return respond({error:'BODY_TOO_LARGE'},413);
    let input; try { input=JSON.parse(raw); } catch { return respond({error:"INVALID_SUBMISSION"},400); }
    if (!input || typeof input!=="object" || Array.isArray(input))return respond({error:"INVALID_SUBMISSION"},400);
    const action=input.action;
    if(action==='health')return respond({ok:true,version:'bridge-3'});
    if(action==='ack') {
      if(!/^[a-f0-9]{64}$/.test(input.token || ''))return respond({error:'INVALID_ACK'},400);
      return respond(await rpc('bridge_ack',{p_hash:await hash(input.token)}));
    }
    if(action==='partner_response') {
      if(!/^[a-f0-9]{64}$/.test(input.token || ''))throw new Error('INVALID_ACK');
      return respond(await rpc('bridge_partner_response',{p_hash:await hash(input.token),p_decision:input.decision,p_owner:String(input.owner || ''),p_steps:String(input.next_steps || '')}));
    }
    if(action==='intake') {
      if(input._gotcha)return respond({error:'INVALID_SUBMISSION'},400);
      const {reference,payload}=validateIntake(input);
      const ip=req.headers.get('x-forwarded-for')?.split(',')[0] || 'unknown';
      const bucket=await hash(service+ip);
      return respond({ok:true,...await rpc('bridge_receive',{p_ref:reference,p_payload:payload,p_fingerprint:await hash(JSON.stringify(payload)),p_bucket:bucket,p_test:false,p_receipt:receiptBody(reference,payload)})});
    }
    if(!await operator(req))return respond({error:'UNAUTHORIZED'},401);
    if(action==='list') {
      const offset=Number(input.offset ?? 0);
      if(!Number.isSafeInteger(offset)||offset<0||offset>1000000)throw new Error('INVALID_FIELD');
      const [page,partners]=await Promise.all([db('bridge_enquiries?order=created_at.desc,reference.asc&limit=26&offset='+offset),allRows('bridge_partners?order=company,id')]);
      const enquiries=page.slice(0,25), refs=enquiries.map((e:any)=>e.reference);
      const filter='reference=in.('+refs.join(',')+')';
      const [deliveries,events]=refs.length?await Promise.all([allRows('bridge_deliveries?'+filter+'&order=created_at.desc,id'),allRows('bridge_events?'+filter+'&order=id.desc')]):[[],[]];
      return respond({enquiries,partners,deliveries,events,offset,has_more:page.length>25});
    }
    if(action==='import') {
      const {reference,payload}=validateIntake(input);
      if(input.is_test===true && payload.email!=='privatecharteroffice@gmail.com')throw new Error('TEST_EMAIL_REQUIRED');
      return respond({ok:true,...await rpc('bridge_import',{p_ref:reference,p_payload:payload,p_fingerprint:await hash(JSON.stringify(payload)),p_test:input.is_test===true,p_receipt:receiptBody(reference,payload),p_evidence:String(input.evidence || '')})});
    }
    if(action==='test_intake') {
      const {reference,payload}=validateIntake(input);
      if(payload.email!=='privatecharteroffice@gmail.com')throw new Error('TEST_EMAIL_REQUIRED');
      return respond({ok:true,...await rpc('bridge_receive',{p_ref:reference,p_payload:payload,p_fingerprint:await hash(JSON.stringify(payload)),p_bucket:'operator-test',p_test:true,p_receipt:'TEST ONLY\n\n'+receiptBody(reference,payload)})});
    }
    if(action==='partner') {
      const company=String(input.company || '').trim(),email=String(input.email || '').trim(),territories=String(input.territories || '').trim(),evidence=String(input.terms_evidence || '').trim();
      if(!company || company.length>180 || !EMAIL.test(email) || !territories || territories.length>500 || evidence.length<11 || evidence.length>2000 || input.verified!==true)throw new Error('PARTNER_DETAILS_REQUIRED');
      if(input.is_test && email!=='privatecharteroffice@gmail.com')throw new Error('TEST_EMAIL_REQUIRED');
      return respond(await db('bridge_partners','POST',{company,email,territories,terms_evidence:evidence,verified:true,active:true,is_test:input.is_test===true,minimum_budget_gbp:0}));
    }
    if(action==='queue') {
      if(!/^PCO-[A-Z0-9-]{8,75}$/.test(input.reference || '') || !/^[a-f0-9-]{36}$/.test(input.partner_id || ''))throw new Error('INVALID_REFERENCE');
      const [e]=await db('bridge_enquiries?reference=eq.'+input.reference);const [p]=await db('bridge_partners?id=eq.'+input.partner_id);
      if(!e || !p)throw new Error('NOT_FOUND');
      const token=Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('');
      const link='https://velaris-private-charter.vercel.app/bridge/ack.html#'+token;
      const d=await rpc('bridge_queue_checked',{p_revision:input.revision,p_ref:e.reference,p_partner:p.id,p_subject:(e.is_test?'TEST ONLY — ':'')+'Charter handover — '+e.reference,p_body:handoverBody(e.reference,e.payload,p.company,link),p_ack_hash:await hash(token)});
      return respond({delivery:d});
    }
    if(action==='office') {
      if(!/^PCO-[A-Z0-9-]{8,75}$/.test(input.reference || ''))throw new Error('INVALID_REFERENCE');
      let payload=null;
      if(input.operation==='correct') { const [e]=await db('bridge_enquiries?reference=eq.'+input.reference); if(!e)throw new Error('NOT_FOUND'); payload=validateIntake({...e.payload,...input.payload,enquiry_reference:e.reference,service_acknowledgement:'accepted'}).payload; if(e.is_test && payload.email!=='privatecharteroffice@gmail.com')throw new Error('TEST_EMAIL_REQUIRED'); }
      return respond(await rpc('bridge_office',{p_ref:input.reference,p_revision:input.revision,p_action:input.operation,p_evidence:String(input.evidence || ''),p_payload:payload,p_due:input.due || null}));
    }
    if(action==='recover') {
      if(!/^[a-f0-9-]{36}$/.test(input.delivery_id || ''))throw new Error('INVALID_REFERENCE');
      return respond(await rpc('bridge_recover',{p_id:input.delivery_id,p_action:input.recovery,p_message:input.gmail_message_id || null}));
    }
    return respond({error:'BAD_ACTION'},400);
  } catch(e) {
    const message=e instanceof Error?e.message:'INTERNAL_ERROR';
    const known=['REFERENCE_CONFLICT','RATE_LIMIT','INVALID_FIELD','MISSING_REQUIREMENTS','INVALID_EMAIL','SERVICE_ACKNOWLEDGEMENT_REQUIRED','INVALID_REFERENCE','PARTNER_NOT_APPROVED','TEST_LIVE_MISMATCH','SHARING_PERMISSION_REQUIRED','ALREADY_ROUTED','INVALID_ACK','NOT_SENT','NOT_FOUND','RETRY_REQUIRES_CONFIRMED_FAILURE','EVIDENCE_REQUIRED','PARTNER_DETAILS_REQUIRED','TEST_EMAIL_REQUIRED','BAD_ACTION','ENQUIRY_INACTIVE','RESPONSE_REQUIRED','RESPONSE_ALREADY_RECORDED','STALE_REVISION','DEADLINE_REQUIRED','RESOLVE_SEND_FIRST','HANDOVER_NOT_COMPLETE'];
    const error=known.find(x=>message.includes(x)) || 'SERVICE_UNAVAILABLE';
    return respond({error},error==='REFERENCE_CONFLICT'?409:error==='RATE_LIMIT'?429:error==='SERVICE_UNAVAILABLE'?503:400);
  }
});
