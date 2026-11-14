# callshelf

เปลี่ยน IP ขาออกของเครื่องด้วย Cloudflare WARP — ไม่รีบูตเราเตอร์ ไม่ตัดเน็ตบ้าน ไม่ยุ่งกับบัญชีหรือโควต้าของบริการอื่น

มีแอพหน้าต่าง (GUI) บน Windows และตัวสั่งงานแบบ CLI บน Windows/Linux

## ต้องมี

- Windows 10/11 สำหรับ GUI และ CLI แบบ PowerShell
- Linux สำหรับ CLI แบบ Bash
- Cloudflare WARP CLI และ `curl` ติดตั้งและเชื่อมต่อไว้แล้วบนระบบปฏิบัติการที่ใช้งาน
- ตั้งโหมด proxy ครั้งเดียว (แนะนำ — ทราฟฟิกอื่นของเครื่องไม่เปลี่ยนเส้นทาง):

```powershell
warp-cli mode proxy
warp-cli proxy port 40000
warp-cli connect
```

ถ้าใช้โหมดเต็ม (`warp-cli mode warp`) สคริปต์ก็ยังอ่าน IP ผ่าน tunnel ได้ แต่ทราฟฟิกทั้งเครื่องจะวิ่งผ่าน WARP

## แอพ (GUI)

ดับเบิลคลิก `callshelf.cmd`

หน้าต่างจะแสดง

- IP ขาออกปัจจุบัน
- โหมดของ WARP (proxy หรือ full tunnel)
- ปุ่ม **เปลี่ยน IP**
- ช่อง **หมุนอัตโนมัติทุก N นาที**
- บันทึกผลด้านล่าง (เวลา, IP ก่อน → หลัง)

ปิดหน้าต่าง = หยุดทุกอย่าง ไม่มี process ค้าง

แอพเป็นสคริปต์ PowerShell ที่รันบน `powershell.exe` ที่ Windows เซ็นชื่อให้อยู่แล้ว จึงเปิดได้บนเครื่องที่ Smart App Control บล็อกไฟล์ `.exe` ที่ compile เอง

## ในแอพ OpenCode

มีแผงของ callshelf อยู่ใน OpenCode Desktop ด้วย — IP ปัจจุบัน, ปุ่มเปลี่ยน IP, log ผลลัพธ์ และปุ่มลัดบน titlebar

ติดตั้ง:

```powershell
# จากโฟลเดอร์ที่โคลน repo นี้มา
powershell -ExecutionPolicy Bypass -File .\plugin\install.ps1
```

สคริปต์จะก๊อปตัวปลั๊กอินกับ `rotate.ps1` ไปที่ `%USERPROFILE%\.config\opencode\plugins\callshelf`

ในแอพ:

- ปุ่มรูปโลกบน titlebar = เปลี่ยน IP ทันที ไม่ต้องเปิดแผง
- แผง **การเชื่อมต่อ** เปิดจากเมนูเลย์เอาต์ด้านขวาบนของ session
- คำสั่งใน command palette: *เปิดแผงการเชื่อมต่อ*, *เปลี่ยน IP ตอนนี้*

ตัวปลั๊กอินเป็น GUI plugin ของ OpenCode (`@opencode/plugin/gui`) ตัว bundle ที่ build แล้วอยู่ใน `plugin/gui-experimental.cjs` ไม่ต้องมี Node หรือ Vite ตอนติดตั้ง

แก้โค้ดแล้ว build ใหม่:

```powershell
cd plugin
npm install
npx vite build
```

## CLI

### Windows

```powershell
# ดู IP ปัจจุบัน
.\rotate.ps1

# เปลี่ยน IP
.\rotate.ps1 -Rotate

# เปลี่ยนแบบบังคับลงทะเบียนใหม่ (ใช้เมื่อ reconnect แล้ว IP ยังเดิม)
.\rotate.ps1 -Rotate -Deep

# ให้สคริปต์อื่นอ่านผล
.\rotate.ps1 -Rotate -Json
```

ดับเบิลคลิก `rotate.cmd` จะได้เมนูแบบกดง่าย (ใส่ `-Rotate` ต่อท้ายก็ได้)

### Linux

ใช้ `rotate.sh` ซึ่งเรียก `warp-cli` และ `curl` ที่ติดตั้งอยู่ในระบบ:

```bash
# ดู IP และสถานะ WARP
./rotate.sh

# เปลี่ยน IP
./rotate.sh --rotate

# บังคับลงทะเบียน WARP ใหม่
./rotate.sh --deep

# ส่งผลลัพธ์เป็น JSON
./rotate.sh --rotate --json
```

ไม่ต้องติดตั้งแพ็กเกจเพิ่มเติม; ต้องติดตั้งและเชื่อมต่อ Cloudflare WARP รวมถึงติดตั้ง `curl` ก่อนใช้งาน

ผลลัพธ์ปกติ:

```
  203.0.113.7 -> 198.51.100.42  (reconnect, 2.4s)
```

## ค่า exit

| code | ความหมาย |
|---|---|
| `0` | ได้ IP ใหม่แล้ว |
| `1` | ไม่เปลี่ยน / WARP ไม่ตอบ / เป็น registration ขององค์กร |

## ไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `callshelf.cmd` | เปิดแอพ |
| `callshelf-gui.ps1` | หน้าต่างแอพ |
| `rotate.ps1` | ตัวหมุน IP (ใช้ร่วมกับ CLI และปลั๊กอิน) |
| `rotate.sh` | ตัวหมุน IP สำหรับ Linux CLI |
| `rotate.cmd` | ตัวเรียก CLI แบบกดง่าย |
| `plugin/` | แผงใน OpenCode Desktop (GUI plugin + bundle ที่ build แล้ว) |
| `plugin/install.ps1` | ติดตั้งแผงเข้า OpenCode |
| `tests/rotate-cli.test.sh` | ทดสอบ Linux CLI ด้วยคำสั่งจำลอง |
| `scripts/update-contributors.mjs` | สร้างภาพผู้ร่วมพัฒนาจาก GitHub |
| `.github/workflows/update-contributors.yml` | อัปเดตภาพผู้ร่วมพัฒนาด้วย GitHub Actions |
| `docs/contributors.svg` | ภาพผู้ร่วมพัฒนาใน README |
| `tests/update-contributors.test.mjs` | ทดสอบตัวสร้างภาพและ workflow |

## ผู้ร่วมพัฒนา

[![ผู้มีส่วนร่วมใน callshelf](docs/contributors.svg)](https://github.com/emperhub/callshelf/graphs/contributors)

ภาพนี้อัปเดตอัตโนมัติด้วย GitHub Actions จากรายชื่อ contributors ของ repository

- GitHub Copilot — ร่วมพัฒนา Linux CLI

## หมายเหตุ

- ค่าเริ่มต้นจะ reconnect ก่อน (~2 วินาที) ถ้า IP ยังเดิมจึงค่อยลบ registration แล้วสร้างใหม่ ซึ่งอาจโดน Cloudflare จำกัดความถี่
- ไม่แตะ router, PPPoE, firewall หรือ service อื่นบนเครื่อง
- ถ้า tunnel เป็นขององค์กร (Team/Enterprise/Managed) สคริปต์จะปฏิเสธ ไม่ลบ registration ให้
- เปลี่ยน IP ถี่เกินไปปลายทางอาจมองว่าเป็นพฤติกรรมผิดปกติ เว้นช่วงอย่างน้อย 8–10 วินาที
