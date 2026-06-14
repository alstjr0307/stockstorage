const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const path = require('path');
const keyPath = path.join(__dirname, 'serviceAccountKey.json');
const serviceAccount = require(keyPath);
const client = new SecretManagerServiceClient({ credentials: serviceAccount });
(async () => {
  const [version] = await client.accessSecretVersion({
    name: 'projects/stockstorage-13828/secrets/ANTHROPIC_API_KEY/versions/latest',
  });
  console.log(version.payload.data.toString('utf8').trim());
})().catch(e => { console.error(e.message); process.exit(1); });
