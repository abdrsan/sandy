import test from 'node:test';import assert from 'node:assert/strict';
import {roomStorage} from '../src/state.mjs';import {promises as fs} from 'node:fs';import os from 'node:os';import path from 'node:path';
test('relay state persists credentials encrypted and refuses a wrong key or tampering',async t=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'sandy-state-'));t.after(()=>fs.rm(dir,{recursive:true,force:true}));
 const file=path.join(dir,'state.enc'),store=roomStorage(file,'a'.repeat(43));const rooms=[{id:'r',push:{token:'sensitive-push-token'}}];
 await store.save(rooms);assert.deepEqual(await store.load(),rooms);
 const bytes=await fs.readFile(file);assert.ok(!bytes.includes(Buffer.from('sensitive-push-token')));
 assert.equal((await fs.stat(file)).mode&0o777,0o600);
 await assert.rejects(roomStorage(file,'b'.repeat(43)).load());bytes[bytes.length-1]^=1;await fs.writeFile(file,bytes);await assert.rejects(store.load());
});
