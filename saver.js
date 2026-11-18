const express = require('express');
const crypto = require('crypto');
const app = express();

// Client က ပို့တဲ့ Form Data တွေကို ဖတ်ဖို့
app.use(express.urlencoded({ extended: true }));

// ⚠️ ဒီ Secret က Client Code ထဲက Secret နဲ့ တိတိကျကျ တူရပါမယ်
const SECRET = 'Vm8Lk7Uj2JmsjCPVPVjrLa7zgfx3uz9E';

// ⚠️ မင်းရဲ့ Key တွေကို ဒီမှာ ထည့်ပါ
const KEYS = {
  "VIP-TEST-0001": { expiresAt: 1767225600, maxDevices: 1, devices: [] }
};

app.post('/server', (req, res) => {
  const { game, user_key, serial } = req.body;
  
  // Key ရှိမရှိစစ်
  const keyData = KEYS[user_key];
  if (!keyData) return res.json({ status: false, reason: 'Invalid key' });

  // သက်တမ်းကုန်မကုန်စစ်
  const now = Math.floor(Date.now() / 1000);
  if (keyData.expiresAt && now >= keyData.expiresAt)
    return res.json({ status: false, reason: 'Expired' });

  // Device အရေအတွက်စစ်
  if (keyData.maxDevices && keyData.devices.length >= keyData.maxDevices
      && !keyData.devices.includes(serial))
    return res.json({ status: false, reason: 'Max devices reached' });

  if (!keyData.devices.includes(serial)) keyData.devices.push(serial);

  // Token တွက်
  const token = crypto.createHash('md5')
    .update(`${game}-${user_key}-${serial}-${SECRET}`)
    .digest('hex');

  // အောင်မြင်ကြောင်း ပြန်ပို့
  res.json({ status: true, data: { token, rng: now } });
});

// Server Run
app.listen(process.env.PORT || 3000, () => console.log('Server running'));
