const path = require('path');
const keyPath = path.join(__dirname, 'serviceAccountKey.json');
const { GoogleAuth } = require('google-auth-library');
const https = require('https');

(async () => {
  const auth = new GoogleAuth({
    keyFile: keyPath,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const token = await auth.getAccessToken();
  const url = 'https://secretmanager.googleapis.com/v1/projects/stockstorage-13828/secrets/ANTHROPIC_API_KEY/versions/latest:access';
  const req = https.request(url, {
    headers: { Authorization: `Bearer ${token}` },
  }, (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
      try {
        const json = JSON.parse(data);
        if (json.payload?.data) {
          const decoded = Buffer.from(json.payload.data, 'base64').toString('utf8');
          console.log(decoded.trim());
        } else {
          console.error('응답:', JSON.stringify(json).slice(0, 300));
          process.exit(1);
        }
      } catch(e) {
        console.error('파싱 오류:', data.slice(0, 300));
        process.exit(1);
      }
    });
  });
  req.on('error', e => { console.error(e.message); process.exit(1); });
  req.end();
})().catch(e => { console.error(e.message); process.exit(1); });
