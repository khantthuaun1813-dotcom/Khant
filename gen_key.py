#!/usr/bin/env python3
"""ZETxLabs key manager - keys.json ကို စီမံပေးတဲ့ script (ကိုယ့်ကွန်ပျူတာ/Termux မှာ run)

  python3 gen_key.py add --days 30 --devices 2 --note "Mg Mg"   -> key အသစ်ထုတ်
  python3 gen_key.py ban KEY            -> ban
  python3 gen_key.py unban KEY          -> ban ဖြုတ်
  python3 gen_key.py adddev KEY DV-XXXXXXXXXXXX   -> ဖုန်း device ID ထည့်
  python3 gen_key.py rmdev KEY DV-XXXXXXXXXXXX    -> device ID ဖြုတ်
  python3 gen_key.py extend KEY 30      -> ရက် ၃၀ တိုး
  python3 gen_key.py delete KEY         -> key ဖျက်
  python3 gen_key.py list               -> စာရင်းကြည့်
ပြီးရင် keys.json ကို GitHub မှာ commit/push လုပ်ပါ။
"""
import json, sys, hashlib, secrets, argparse, datetime, os

FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "keys.json")
ALPHA = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

def h(k): return hashlib.sha256(k.strip().upper().encode()).hexdigest()
def load():
    try: return json.load(open(FILE, encoding="utf-8"))
    except Exception: return {"keys": {}}
def save(d): json.dump(d, open(FILE, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
def need(d, key):
    e = d["keys"].get(h(key))
    if not e: sys.exit("key မတွေ့ပါ")
    return e
def today(): return datetime.datetime.now(datetime.timezone.utc).date()

def main():
    a = argparse.ArgumentParser()
    a.add_argument("cmd")
    a.add_argument("arg1", nargs="?"); a.add_argument("arg2", nargs="?")
    a.add_argument("--days", type=int, default=30)
    a.add_argument("--devices", type=int, default=1)
    a.add_argument("--note", default="")
    a.add_argument("--key", default="")
    x = a.parse_args(); d = load()

    if x.cmd == "add":
        key = x.key.upper() or "ZETX-" + "".join(secrets.choice(ALPHA) for _ in range(4)) + "-" + "".join(secrets.choice(ALPHA) for _ in range(4))
        d["keys"][h(key)] = {"note": x.note, "expires": str(today() + datetime.timedelta(days=x.days)),
                              "banned": False, "max_devices": x.devices, "devices": []}
        save(d); print("KEY:", key, "| expires:", d["keys"][h(key)]["expires"], "| devices:", x.devices)
    elif x.cmd in ("ban", "unban"):
        need(d, x.arg1)["banned"] = (x.cmd == "ban"); save(d); print("OK", x.cmd)
    elif x.cmd == "adddev":
        e = need(d, x.arg1); dv = x.arg2.upper()
        if dv not in e["devices"]: e["devices"].append(dv)
        if len(e["devices"]) > e["max_devices"]: print("သတိ: devices အရေအတွက်က max_devices ထက်များနေပြီ (ပြည့်ပါပြီ)")
        save(d); print("OK", e["devices"])
    elif x.cmd == "rmdev":
        e = need(d, x.arg1); dv = x.arg2.upper()
        e["devices"] = [i for i in e["devices"] if i != dv]; save(d); print("OK", e["devices"])
    elif x.cmd == "extend":
        e = need(d, x.arg1); base = max(today(), datetime.date.fromisoformat(e["expires"]))
        e["expires"] = str(base + datetime.timedelta(days=int(x.arg2))); save(d); print("new expiry", e["expires"])
    elif x.cmd == "delete":
        need(d, x.arg1); del d["keys"][h(x.arg1)]; save(d); print("deleted")
    elif x.cmd == "list":
        for k, e in d["keys"].items():
            print(k[:8], "|", e.get("note", ""), "| exp", e["expires"], "| banned" if e["banned"] else "| ok",
                  "| dev %d/%d" % (len(e["devices"]), e["max_devices"]), e["devices"])
    else:
        print(__doc__)
main()
