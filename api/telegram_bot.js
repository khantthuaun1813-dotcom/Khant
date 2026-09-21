// api/telegram_bot.js
const TELEGRAM_BOT_TOKEN = "YOUR_BOT_TOKEN_HERE";
const TELEGRAM_ADMIN_CHAT_ID = "YOUR_CHAT_ID_HERE";

export default async function handler(req, res) {
    if (req.method !== 'POST') {
        return res.status(405).json({ ok: false });
    }

    const update = req.body;
    
    if (update.message) {
        const chatId = update.message.chat.id;
        const text = update.message.text || '';
        const userId = update.message.from.id;

        if (text === '/start') {
            await sendMessage(chatId, 
                "🎮 *Khant Mod Bot*\n\n" +
                "Commands:\n" +
                "/genkey <days> - Key အသစ် ဖန်တီး\n" +
                "/help - အကူအညီ"
            );
        }
        else if (text.startsWith('/genkey')) {
            if (String(userId) !== TELEGRAM_ADMIN_CHAT_ID) {
                await sendMessage(chatId, "❌ Admin သာ သုံးလို့ရပါတယ်");
                return res.status(200).json({ ok: true });
            }

            const days = parseInt(text.split(' ')[1]) || 30;
            const newKey = generateKey();
            const expiry = new Date();
            expiry.setDate(expiry.getDate() + days);

            await sendMessage(chatId,
                "✅ *Key အသစ် ဖန်တီးပြီးပါပြီ*\n\n" +
                "🔑 Key: `" + newKey + "`\n" +
                "📅 Expiry: " + expiry.toISOString().split('T')[0] + "\n" +
                "⏱ Duration: " + days + " days\n\n" +
                "⚠️ Key ကို `api/check_vip_key.js` ဖိုင်ထဲမှာ ထည့်ပါ"
            );
        }
        else if (text === '/help') {
            await sendMessage(chatId,
                "📖 *အကူအညီ*\n\n" +
                "• Key ထည့်ဖို့: `Khant.txt` ဖိုင်ထဲမှာ Key ကို ရေးပါ\n" +
                "• Key ဝယ်ဖို့: @OnlyKhaingKhaing ကို ဆက်သွယ်ပါ"
            );
        }
    }

    return res.status(200).json({ ok: true });
}

async function sendMessage(chatId, text) {
    const url = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`;
    await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            chat_id: chatId,
            text: text,
            parse_mode: 'Markdown'
        })
    });
}

function generateKey() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let key = 'KEYAUTH-';
    for (let i = 0; i < 12; i++) {
        key += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return key;
}
