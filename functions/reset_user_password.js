// Usage:
//   node reset_user_password.js <email> [newPassword]
// If newPassword omitted, sends a password reset email link instead.

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

async function main() {
  const email = process.argv[2];
  const newPassword = process.argv[3];

  if (!email) {
    console.error('Usage: node reset_user_password.js <email> [newPassword]');
    process.exit(1);
  }

  const user = await admin.auth().getUserByEmail(email);
  console.log('Found user:', user.uid, user.email);

  if (newPassword) {
    await admin.auth().updateUser(user.uid, { password: newPassword });
    console.log(`Password updated for ${email}.`);
    console.log(`New password: ${newPassword}`);
  } else {
    const link = await admin.auth().generatePasswordResetLink(email);
    console.log('Password reset link (send to user):');
    console.log(link);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
