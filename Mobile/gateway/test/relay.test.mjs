import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { Relay, server } from '../src/server.mjs';
const token=()=>randomBytes(32).toString('base64url');
const hash=x=>createHash('sha256').update(x).digest('hex');
async function fixture(t) {
  const admin=token(),mac=token(),phone=token(),room=token();
  let pushed=0;let time=Date.now();
  const relay=new Relay({adminToken:admin,clock:()=>time,push:async()=>{pushed++}});
  const s=server(relay);await new Promise(resolve=>s.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{s.closeAllConnections();s.close(resolve)}));
  const url='http://127.0.0.1:'+s.address().port;
  async function call(path,{role='mac',auth=mac,body,method=body?'POST':'GET',origin}={}) {
    return fetch(url+path,{method,headers:{authorization:'Bearer '+auth,'x-sandy-role':role,...(origin?{origin}:{}),'content-type':'application/json'},body:body?JSON.stringify(body):undefined});
  }
  const create=()=>call('/v1/rooms',{auth:admin,body:{room,macHash:hash(mac),phoneHash:hash(phone)}});
  const envelope=()=>({version:1,room,id:crypto.randomUUID(),sentAt:time,senderKey:Buffer.alloc(65,1).toString('base64'),encapsulatedKey:Buffer.alloc(65,2).toString('base64'),ciphertext:Buffer.alloc(64,3).toString('base64')});
  return {relay,call,create,envelope,room,mac,phone,admin,advance:n=>time+=n,pushed:()=>pushed};
}
test('fails closed without a strong admin credential',()=>assert.throws(()=>new Relay({adminToken:'short'})));
test('room creation authenticates before allocating state',async t=>{
  const f=await fixture(t);
  assert.equal((await f.call('/v1/rooms',{auth:'wrong',body:{room:f.room}})).status,401);
  assert.equal(f.relay.rooms.size,0);assert.equal((await f.create()).status,200);
  assert.equal((await f.call('/v1/rooms/'+f.room+'/messages',{auth:'wrong'})).status,401);
  assert.equal((await f.call('/v1/rooms/'+f.room+'/messages',{role:'phone',auth:f.mac})).status,401);
});
test('isolates roles and rooms, bounds opaque delivery and retries',async t=>{
  const f=await fixture(t);await f.create();const e=f.envelope();const path='/v1/rooms/'+f.room+'/messages';
  assert.equal((await f.call(path,{body:{envelope:e}})).status,200);
  assert.equal((await f.call(path,{body:{envelope:e}})).status,200);
  assert.equal((await(await f.call(path)).json()).messages.length,0);
  const batch=await(await f.call(path,{role:'phone',auth:f.phone})).json();assert.equal(batch.messages.length,1);
  assert.deepEqual(batch.messages[0],e);
  assert.equal((await(await f.call(path+'?after='+batch.cursor,{role:'phone',auth:f.phone})).json()).messages.length,0);
  assert.equal((await f.call(path,{body:{envelope:{...e,room:token()}}})).status,400);
  f.advance(121000);assert.equal((await(await f.call(path,{role:'phone',auth:f.phone})).json()).messages.length,0);
});
test('revocation invalidates both credentials and drops queued ciphertext',async t=>{
  const f=await fixture(t);await f.create();const base='/v1/rooms/'+f.room;
  await f.call(base+'/messages',{body:{envelope:f.envelope()}});
  assert.equal((await f.call(base,{method:'DELETE'})).status,200);
  assert.equal((await f.call(base+'/messages',{role:'phone',auth:f.phone})).status,401);
  assert.equal(f.relay.rooms.size,0);
});
test('browser origins and actual oversized bodies are rejected',async t=>{
  const f=await fixture(t);await f.create();const path='/v1/rooms/'+f.room+'/messages';
  assert.equal((await f.call(path,{origin:'https://attacker.example'})).status,403);
  assert.equal((await f.call(path,{body:{x:'x'.repeat(71000)}})).status,413);
});
test('push uses the separate phone registration and is throttled',async t=>{
  const f=await fixture(t);await f.create();const base='/v1/rooms/'+f.room;
  assert.equal((await f.call(base+'/push',{body:{platform:'fcm',token:token()}})).status,404);
  assert.equal((await f.call(base+'/push',{role:'phone',auth:f.phone,body:{platform:'fcm',token:token()}})).status,200);
  await f.call(base+'/messages',{body:{envelope:f.envelope(),notify:true}});
  assert.equal(f.pushed(),1);
});
