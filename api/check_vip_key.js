// api/check_vip_key.js
export default function handler(req, res) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') return res.status(200).end();
    if (req.method !== 'POST') {
        return res.status(405).json({ status: false, msg: 'Method Not Allowed' });
    }

    const { key, hwid, game_id } = req.body || {};

    // ═══════════════════════════════════════════════
    // ⚠️ Key စာရင်း (Bot ကနေ ထည့်ပေးမယ့် Key တွေ ဒီနေရာမှာ ထည့်ပါ)
    // ═══════════════════════════════════════════════
    const validKeys = {
        "KEYAUTH-ABS2Z4V7UHLK": {
            expiry: "2026-10-21",
            max_devices: 1,
            devices: []
        }
    };

    if (!key || !hwid) {
        return res.status(200).json({ status: false, msg: 'Missing key or hwid' });
    }

    const keyData = validKeys[key];
    if (!keyData) {
        return res.status(200).json({ status: false, msg: 'Invalid key' });
    }

    const expiryDate = new Date(keyData.expiry + 'T23:59:59');
    if (new Date() > expiryDate) {
        return res.status(200).json({ status: false, msg: 'Key expired: ' + keyData.expiry });
    }

    const deviceIndex = keyData.devices.indexOf(hwid);
    if (deviceIndex === -1) {
        if (keyData.devices.length >= keyData.max_devices) {
            return res.status(200).json({ 
                status: false, 
                msg: 'Device limit reached! (Max: ' + keyData.max_devices + ')' 
            });
        }
        keyData.devices.push(hwid);
    }

    return res.status(200).json({
        status: true,
        type: 'VIP',
        msg: 'VIP Login Success',
        expiry: keyData.expiry
    });
}
