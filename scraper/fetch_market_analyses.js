const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const serviceAccount = require('./service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function main() {
  const snap = await db
    .collection('market_analyses')
    .orderBy('createdAt', 'desc')
    .limit(50)
    .get();

  const items = [];
  snap.forEach((doc) => {
    const d = doc.data();
    items.push({
      id: doc.id,
      title: d.title || '',
      body: d.body || '',
      createdAt: d.createdAt ? d.createdAt.toDate().toISOString() : null,
    });
  });

  const out = path.join(__dirname, 'out', 'market_analyses.json');
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, JSON.stringify(items, null, 2), 'utf8');
  console.log(`Saved ${items.length} analyses to ${out}`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
