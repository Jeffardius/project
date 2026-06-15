
---

## ✅ What this script ✅ What this script does differently does differently

- **

- **Removes ALLRemoves ALL allow rules** (not just the ones named allow rules** (not just the `Lab_* ones named `Lab_*`)
- **Explicitly dis`)
- **Exables** the built‑plicitly disables**in rules that * the built‑in rulescould* allow ping (they that *could* allow ping are usually (they are usually off by default, but we force them off)
- **T off by default, but we force them off)
- **Turns the firewall ON** –urns the firewall ON** – because when because when the firewall is OFF the firewall is OFF, everything is allowed, everything is allowed (including ping). (including ping). If you want ping If you want ping blocked, firewall **must** be ON blocked, firewall **must** be ON.
- **Creates a shortcut**.
- **Creates a shortcut** (optional) to quickly re‑ (optional) to quickly re‑block ping if you ever accidentallyblock ping if you ever accidentally turn it back on turn it back on.

---

## 🔁 To.

---

## 🔁 To re‑allow ping later ( re‑allow ping later (if needed)

Run this (if needed)

Run this (as Admin) – oras Admin) – or use the shortcut from the use the shortcut from the previous previous installer installer that that * *enables* pingenables* ping:

```powershell:

```powershell
netsh adv
netsh advfirewall firewall addfirewall firewall add rule name="Allow rule name="Allow_ALL_IC_ALL_ICMPv4"MPv4" dir=in protocol dir=in protocol=icmpv=icmpv4 action=allow4 action=allow
