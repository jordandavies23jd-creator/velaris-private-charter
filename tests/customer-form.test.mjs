import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const script=readFileSync(new URL('../script.js',import.meta.url),'utf8');
function setup(fetch, {uuid=true, success=true}={}) {
  let handler;
  const button={disabled:false,innerHTML:'Submit',textContent:''};
  const status={textContent:'',focus(){}};
  const form={elements:{enquiry_reference:{value:''}},style:{},fields:{name:'Office test',email:'office@example.com'},reportValidity:()=>true,querySelector:()=>button,setAttribute(){},removeAttribute(){},addEventListener(_,fn){handler=fn;}};
  const confirmation={style:{},focus(){}},reference={textContent:''};
  const elements={briefForm:form,formStatus:status,...(success?{success:confirmation,successReference:reference}:{})};
  class Data extends Map {constructor(f){super(Object.entries({...f.fields,enquiry_reference:f.elements.enquiry_reference.value}));}}
  vm.runInNewContext(script,{document:{getElementById:id=>elements[id],querySelectorAll:()=>[]},crypto:{...(uuid?{randomUUID:()=> 'test-reference-123'}:{}),getRandomValues:a=>a.fill(1)},FormData:Data,AbortController,setTimeout,clearTimeout,fetch});
  return {form,status,button,confirmation,reference,submit:()=>handler({preventDefault(){},currentTarget:form})};
}
test('form remains usable when animation API is unavailable; confirmed details are retained',async()=>{
  const ui=setup(async()=>({ok:true,json:async()=>({ok:true})}));await ui.submit();
  assert.match(ui.status.textContent,/has been saved/);assert.equal(ui.form.fields.email,'office@example.com');assert.equal(ui.form.style.display,'none');assert.match(ui.reference.textContent,/PCO-TEST-REFERENCE-123/);
});
test('ambiguous failure retries identical payload but blocks edited payload',async()=>{
  const requests=[];const ui=setup(async(_,options)=>{requests.push(options.body);throw Error('Connection interrupted');});
  await ui.submit();await ui.submit();assert.equal(requests.length,2);assert.equal(requests[0],requests[1]);assert.equal(ui.button.disabled,false);assert.match(ui.status.textContent,/PCO-TEST-REFERENCE-123/);
  ui.form.fields.email='changed@example.com';await ui.submit();assert.equal(requests.length,2);assert.match(ui.status.textContent,/may already be saved/);
});
test('missing success panel still shows confirmed submission without losing details',async()=>{
  const ui=setup(async()=>({ok:true,json:async()=>({ok:true})}),{success:false});await ui.submit();assert.match(ui.status.textContent,/has been saved/);assert.equal(ui.form.fields.name,'Office test');
});
test('older secure browsers can generate a stable reference without randomUUID',async()=>{
  const ui=setup(async()=>({ok:false,json:async()=>({ok:false})}),{uuid:false});assert.match(ui.form.elements.enquiry_reference.value,/^PCO-[A-F0-9]{32}$/);await ui.submit();assert.match(ui.status.textContent,/couldn’t confirm/);
});
