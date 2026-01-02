# 🎧 Mumble Server Generator (Murmur)

A simple **bash script** to create and manage **fully isolated Mumble (Murmur) servers** on a clean Debian system.

This script:
- Uses a **full official Murmur configuration**
- Injects a **preconfigured SQLite database** (channels already created)
- Creates **one systemd service per server**
- Supports **automatic port detection** or manual port selection
- Allows **full destruction** of a server with a single command

---

## ✨ Features

- ✅ Full Murmur configuration (no minimal / broken config)
- ✅ Preloaded SQLite database (channels already exist)
- ✅ One server = one config, one DB, one service
- ✅ Automatic port increment (or manual `-p`)
- ✅ Clean systemd integration
- ✅ Logs enabled
- ✅ One-command full removal (`-d`)
- ✅ Works on a **fresh Debian server**

---

## 📦 Requirements

- Debian 11 / 12 / Testing (Trixie)
- Root access

The script installs everything automatically:
- `mumble-server`
- `curl`
- `unzip`
- `iproute2`

---

## 🚀 Installation

Clone the repository:

```bash
git clone https://github.com/Dolyyyy/murmurd-mumble-generator.git
cd murmurd-mumble-generator
chmod +x mumbleserver.sh
```

🛠 Usage
➕ Create a server
``bash mumbleserver.sh myserver``

With a custom port:

``bash mumbleserver.sh -p 65000 myserver``

If the port is already in use, the script automatically increments it.
