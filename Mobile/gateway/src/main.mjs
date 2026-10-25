import { Relay, server } from './server.mjs';
import { pushSender } from './push.mjs';
import { roomStorage } from './state.mjs';
const port=Number(process.env.PORT ?? 8787);
if(!Number.isInteger(port)||port<1||port>65535)throw Error('Invalid port');
const admin=process.env.SANDY_RELAY_ADMIN_TOKEN;
if(!admin || admin.length<43)throw Error('A 256-bit relay admin token is required');
const storage=roomStorage(process.env.SANDY_RELAY_STATE_FILE ?? './state/relay.enc',admin);
const relay=new Relay({adminToken:admin,providers:{apns:!!process.env.APNS_KEY_FILE,"apns-live":!!process.env.APNS_KEY_FILE,fcm:!!process.env.FCM_KEY_FILE},push:pushSender(process.env),changed:()=>{
 const rooms=[...relay.rooms].map(([id,r])=>({id,macHash:r.macHash,phoneHash:r.phoneHash,push:r.push,livePush:r.livePush,expires:r.expires}));
 storage.save(rooms).catch(()=>{process.stderr.write('Could not persist relay credentials; stopping safely\n');process.exitCode=1;service.close();});
}});
for(const r of await storage.load()) {
 if(typeof r.id!=='string'||!/^[A-Za-z0-9_-]{22,64}$/.test(r.id)||!Number.isFinite(r.expires)||!(/^[0-9a-f]{64}$/).test(r.macHash)||!(/^[0-9a-f]{64}$/).test(r.phoneHash))throw Error('Invalid relay credentials');
 if(r.expires>Date.now())relay.rooms.set(r.id,{...r,queues:{mac:[],phone:[]},seq:0});
}
const service=server(relay);
service.listen(port,process.env.BIND ?? '127.0.0.1',()=>process.stdout.write('Sandy encrypted relay ready\n'));
setInterval(()=>{for(const [id,room] of relay.rooms)if(room.expires<Date.now())relay.rooms.delete(id);},60000).unref();
