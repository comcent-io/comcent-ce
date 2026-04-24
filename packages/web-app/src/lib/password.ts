import bcrypt from 'bcrypt';

// Hash password
const saltRounds = 10; // Number of salt rounds for bcrypt

export function hashPassword(plaintextPassword: string): Promise<string> {
  return new Promise((resolve, reject) => {
    bcrypt.hash(plaintextPassword, saltRounds, (err, hash) => {
      if (err) {
        reject(err);
      }
      resolve(hash);
    });
  });
}

export function verifyPassword(plaintextPassword: string, hash: string) {
  return new Promise((resolve, reject) => {
    bcrypt.compare(plaintextPassword, hash, (err, result) => {
      console.log('verifyPassword', err, result);
      if (err) {
        reject(err);
      }
      resolve(result);
    });
  });
}
