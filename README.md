# callshelf

เปลี่ยน IP ขาออกของเครื่องด้วย Cloudflare WARP — ไม่รีบูตเราเตอร์ ไม่ตัดเน็ตบ้าน ไม่ยุ่งกับบัญชีหรือโควต้าของบริการอื่น

มีทั้งแอพหน้าต่าง (GUI) และตัวสั่งงานแบบ CLI ใช้ตัวหมุนตัวเดียวกัน

## ต้องมี

- Windows 10/11
- Cloudflare WARP: `winget install Cloudflare.Warp`
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

## CLI

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
| `rotate.ps1` | ตัวหมุน IP (ใช้ร่วมกับ CLI) |
| `rotate.cmd` | ตัวเรียก CLI แบบกดง่าย |

## หมายเหตุ

- ค่าเริ่มต้นจะ reconnect ก่อน (~2 วินาที) ถ้า IP ยังเดิมจึงค่อยลบ registration แล้วสร้างใหม่ ซึ่งอาจโดน Cloudflare จำกัดความถี่
- ไม่แตะ router, PPPoE, firewall หรือ service อื่นบนเครื่อง
- ถ้า tunnel เป็นขององค์กร (Team/Enterprise/Managed) สคริปต์จะปฏิเสธ ไม่ลบ registration ให้
- เปลี่ยน IP ถี่เกินไปปลายทางอาจมองว่าเป็นพฤติกรรมผิดปกติ เว้นช่วงอย่างน้อย 8–10 วินาที
