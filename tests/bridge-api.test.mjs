import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {createContext,runInContext} from 'node:vm';
import {webcrypto} from 'node:crypto';
import {EMAIL,validateIntake,handoverBody,receiptBody} from '../supabase/functions/charter-bridge/core.js';

const source=stripTypeScriptTypes(readFileSync(new URL('../supabase/functions/charter-bridge/index.ts',import.meta.url),'utf8').replace(/^import .*\n/,''));
const key='local-fixture-key-'.padEnd(64,'x');
function server(){
 let handler;const calls=[];
 const context=createContext({EMAIL,validateIntake,handoverBody,receiptBody,crypto:webcrypto,TextEncoder,Request,Response,AbortSignal,fetch:async(url,options)=>{
  const path=url.split('/rest/v1/')[1];calls.push({path,body:options.body&&JSON.parse(options.body)});
  let result=[];
  if(path.startsWith('bridge_operator_keys?'))result=[{key_hash:'fixture'}];
  if(path.startsWith('bridge_enquiries?'))result=Array.from({length:26},(_,i)=>({reference:'PCO-FIXTURE-'+String(i).padStart(8,'0')}));
  if(path.startsWith('bridge_deliveries?'))result=Array.from({length:path.includes('offset=0')?500:1},(_,i)=>({id:i,reference:'PCO-FIXTURE-00000000'}));
  if(path==='rpc/bridge_import')result={reference:JSON.parse(options.body).p_ref,duplicate:false};
  return new Response(JSON.stringify(result));
 },Deno:{env:{get:()=> 'fixture'},serve:fn=>handler=fn}});
 runInContext(source,context);
 return {calls,request:(body,authorized=true,origin='https://velaris-private-charter.vercel.app')=>handler(new Request('https://fixture.invalid',{method:'POST',headers:{'Content-Type':'application/json',Origin:origin,...(authorized?{Authorization:'Bearer '+key}:{})},body:JSON.stringify(body)}))};
}
test('office import is protected and rejects a different site origin',async()=>{
 const s=server();assert.equal((await s.request({action:'import'},false)).status,401);assert.equal((await s.request({action:'import'},true,'https://other.invalid')).status,403);assert.equal(s.calls.length,0);
});
test('paged desk loads history for displayed enquiries and reports more pages',async()=>{
 const s=server();const r=await s.request({action:'list',offset:25});assert.equal(r.status,200);const data=await r.json();assert.equal(data.enquiries.length,25);assert.equal(data.has_more,true);assert.equal(data.deliveries.length,501);
 assert.ok(s.calls.some(c=>c.path.includes('offset=25')));
 for(const c of s.calls.filter(c=>/^bridge_(deliveries|events)\?/.test(c.path))){assert.ok(c.path.includes('reference=in.('));assert.ok(c.path.includes('PCO-FIXTURE-00000024'));assert.ok(!c.path.includes('PCO-FIXTURE-00000025'));}
 assert.equal((await s.request({action:'list',offset:-1})).status,400);
});
test('email import retains absence of consent and uses the atomic audited import',async()=>{
 const s=server();const r=await s.request({action:'import',enquiry_reference:'PCO-FIXTURE-IMPORT-001',area:'Greece',dates:'July 2027',guests:'8',budget:'GBP 100000',budget_scope:'Charter fee',name:'Fixture',email:'privatecharteroffice@gmail.com',service_acknowledgement:'accepted',evidence:'Original fixture message consent reviewed.',is_test:true});
 assert.equal(r.status,200);const rpc=s.calls.find(c=>c.path==='rpc/bridge_import');assert.equal(rpc.body.p_payload.sharing_permission,'not_given');assert.equal(rpc.body.p_test,true);assert.equal(rpc.body.p_evidence,'Original fixture message consent reviewed.');
});

test('customer qualification requires office access and preserves explicit confirmation',async()=>{
 const s=server();assert.equal((await s.request({action:'qualify',reference:'PCO-FIXTURE-QUALIFY-001'},false)).status,401);
 const r=await s.request({action:'qualify',reference:'PCO-FIXTURE-QUALIFY-001',revision:0,stage:'confirmed',confirmed:'true',source:'Fixture referrer',evidence:'Customer confirmation fixture evidence.',due:'2027-01-01T12:00:00Z'});
 assert.equal(r.status,200);const call=s.calls.find(c=>c.path==='rpc/bridge_qualify');assert.equal(call.body.p_confirmed,false);assert.equal(call.body.p_source,'Fixture referrer');assert.equal(call.body.p_revision,0);
});
