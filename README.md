# Discord 429 Watchdog

Discord'da **"Messages Failed To Load"** / **HTTP 429** hatası için otomatik kurtarma aracı.

Cloudflare WARP kullanan (ISP engeli aşan) kullanıcıların datacenter IP'si Discord tarafından rate-limit'lenir. Bu araç 429 algıladığında WARP IP rotasyonu yapar, gerekirse Discord'u kontrollü yeniden başlatır.

## Özellikler

- Discord log'unda `429` / `Failed to fetch messages` algılama
- Otomatik WARP disconnect → connect (IP rotasyonu)
- Gerekirse tek seferlik Discord restart
- Saatlik maksimum 3 rotasyon (spam koruması)
- 12 dakika cooldown
- **Çok kullanıcı destekli** — her Windows hesabı kendi instance'ını çalıştırır
- Tek instance mutex (çift çalışma yok)

## Kurulum

### Bu bilgisayarda (tüm kullanıcılar)

1. Bu klasörü sabit bir yere kopyalayın (örn. `C:\ProgramData\Discord429Watchdog`)
2. `kur.bat` dosyasına **sağ tık → Yönetici olarak çalıştır**
3. Bitti — her kullanıcı girişinde otomatik başlar

### Manuel çalıştırma

`Discord429Watchdog.bat` dosyasına çift tıklayın veya:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Discord429Watchdog.ps1
```

### Parametreler

```powershell
.\Discord429Watchdog.ps1 -CheckIntervalSeconds 30   # kontrol aralığı
.\Discord429Watchdog.ps1 -CooldownMinutes 12         # bekleme süresi
.\Discord429Watchdog.ps1 -Force -Once                # tek seferlik zorla
```

## Kaldırma

`kaldir.bat` → **sağ tık → Yönetici olarak çalıştır**

## Log / Durum

| Dosya | Yol |
|-------|-----|
| Watchdog log | `%LOCALAPPDATA%\discord-429-watchdog.log` |
| State | `%LOCALAPPDATA%\discord-429-watchdog.state` |
| Discord log | `%APPDATA%\discord\logs\renderer_js.log` |

İzlemek için:

```powershell
Get-Content "$env:LOCALAPPDATA\discord-429-watchdog.log" -Wait
```

## Gereksinimler

- Windows 10 / 11
- [Cloudflare WARP](https://1.1.1.1/) kurulu (`warp-cli`)
- Discord kurulu

> **Not:** WARP yoksa Discord engeli (ISP DNS/SNI bloğu) aşılamaz; watchdog yalnızca rate-limit kurtarması yapar.

## Nasıl çalışır?

```
429 algıla
    │
    ├─ cooldown içinde mi? ──evet──> bekle
    │
    hayır
    │
    ├─ saatlik limit (<3)? ──hayır──> bekle
    │
    evet
    │
    ├─ WARP disconnect → connect (yeni IP)
    │
    ├─ 90 sn bekle → hâlâ 429?
    │       ├─ evet → Discord restart
    │       └─ hayır → dokunma
    │
    └─ 12 dk cooldown başlat
```

## License

MIT
