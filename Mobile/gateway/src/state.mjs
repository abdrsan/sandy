import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
export function roomStorage(file, adminToken) {
  const key=createHash('sha256').update('sandy-relay-state-v1\0'+adminToken).digest();
  let saving=Promise.resolve();
  return {
    async load() {
      let data;try {data=await fs.readFile(file)}catch(e){if(e.code==='ENOENT')return [];throw e}
      if(data.length>1000000 || data.length<28)throw Error('Invalid relay state');
      const decipher=createDecipheriv('aes-256-gcm',key,data.subarray(0,12));decipher.setAuthTag(data.subarray(12,28));
      const plain=Buffer.concat([decipher.update(data.subarray(28)),decipher.final()]);
      const rooms=JSON.parse(plain.toString());if(!Array.isArray(rooms)||rooms.length>100)throw Error('Invalid relay state');return rooms;
    },
    save(rooms) {
      const value=JSON.stringify(rooms); // Capture now; queues and payloads never enter this snapshot.
      saving=saving.then(async()=>{
        await fs.mkdir(path.dirname(file),{recursive:true,mode:0o700});
        const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);
        const ciphertext=Buffer.concat([cipher.update(value),cipher.final()]);
        const temp=file+'.'+randomBytes(8).toString('hex');
        await fs.writeFile(temp,Buffer.concat([iv,cipher.getAuthTag(),ciphertext]),{mode:0o600,flag:'wx'});
        await fs.rename(temp,file);
      });return saving;
    }
  };
}
