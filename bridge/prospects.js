'use strict';
const endpoint='https://prsmpxewavilnymdaroi.supabase.co/functions/v1/charter-bridge';
let key='',selected=null;
const el=id=>document.getElementById(id);
async function api(input){const r=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+key},body:JSON.stringify(input),signal:AbortSignal.timeout(15000)});const data=await r.json();if(!r.ok)throw Error(data.error||'Unable to load tracker');return data;}
function message(t){el('message').textContent=t;}
function lock(){key='';selected=null;el('key').value='';el('rows').replaceChildren();el('workspace').hidden=true;el('edit').hidden=true;el('access').hidden=false;message('Tracker locked.');}
async function refresh(){const data=await api({action:'prospects'});el('rows').replaceChildren();let overdue=0;for(const p of data.prospects){const due=p.followup_due_at&&new Date(p.followup_due_at);const late=due&&due<new Date()&&['awaiting_reply','qualifying','terms_pending'].includes(p.status);if(late)overdue++;
const card=document.createElement('article');const title=document.createElement('h2');title.textContent=p.company;card.append(title);
for(const text of [p.role+' · '+p.status+(late?' · FOLLOW-UP DUE':''),p.email,p.evidence,'Next: '+p.next_action,'Follow-up: '+(due?due.toLocaleString():'None')]){const para=document.createElement('p');para.textContent=text;card.append(para);}
const button=document.createElement('button');button.textContent='Review / update';button.onclick=()=>edit(p);card.append(button);el('rows').append(card);}
el('counts').textContent=data.prospects.length+' prospects · '+overdue+' due for review';}
function edit(p){selected=p;const f=el('edit');f.hidden=false;el('selected').textContent=p.company;f.elements.status.value=p.status;f.elements.evidence.value=p.evidence;f.elements.next_action.value=p.next_action;const d=p.followup_due_at&&new Date(p.followup_due_at);f.elements.due.value=d?new Date(d-d.getTimezoneOffset()*60000).toISOString().slice(0,16):'';f.scrollIntoView({behavior:'smooth'});}
el('access').onsubmit=async e=>{e.preventDefault();key=el('key').value;el('key').value='';try{await refresh();el('workspace').hidden=false;el('access').hidden=true;message('Tracker opened.');}catch(err){lock();message(err.message);}};
el('refresh').onclick=()=>refresh().then(()=>message('Updated.')).catch(err=>message(err.message));
el('lock').onclick=lock;el('cancel').onclick=()=>{el('edit').hidden=true;selected=null;};
el('edit').onsubmit=async e=>{e.preventDefault();const f=e.target,button=f.querySelector('button');button.disabled=true;try{await api({action:'prospect_update',email:selected.email,revision:selected.revision,status:f.elements.status.value,evidence:f.elements.evidence.value,next_action:f.elements.next_action.value,due:f.elements.due.value?new Date(f.elements.due.value).toISOString():null});f.hidden=true;selected=null;await refresh();message('Reviewed update saved.');}catch(err){message(err.message+' — refresh before retrying if another update was saved.');}finally{button.disabled=false;}};
window.addEventListener('pagehide',lock);
