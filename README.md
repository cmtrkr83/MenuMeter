# MenuMeter

macOS menü çubuğunda CPU, GPU, RAM, SSD ve ağ hızını aynı anda gösteren hafif bir yardımcı uygulama.

## Özellikler

- Beş metrik soldan sağa yan yana: CPU (turuncu), GPU (pembe), RAM (mavi), SSD (mor), Ağ (yeşil). Her metrik kendi halkası ve değeriyle görünür; dönen metin yoktur.
- Değerler 3 saniyede bir güncellenir.
- Sol tık: Activity Monitor'ü açar.
- Sağ tık: ayrıntılı değerler, Activity Monitor, Başlangıçta Aç ve Çıkış menüsü.
- Dock simgesi yoktur; yalnızca menü çubuğunda çalışır.

## Gereksinimler

- macOS 13 veya üzeri.
- Swift 6.4 ve Command Line Tools (tam Xcode gerekmez).

## Derleme ve kurulum

```bash
./scripts/build_app.sh
```

Betik uygulamayı release olarak derler, ad-hoc imzalar ve `~/Applications/MenuMeter.app` konumuna kurar.

## Çalıştırma

```bash
open ~/Applications/MenuMeter.app
```

Başlangıçta açmak için menü çubuğundaki bir öğeye sağ tıklayıp **Başlangıçta Aç** seçeneğini işaretleyin.

## Kaynak hedefi

- Boşta ortalama CPU: %0,2'nin altında
- Fiziksel bellek footprint'i: 20 MB'ın altında (Activity Monitor'deki "Memory" değeri)

## Kaldırma

1. Sağ tık menüsünden **Başlangıçta Aç** işaretini kaldırın.
2. **Çıkış** ile uygulamayı kapatın.
3. `rm -rf ~/Applications/MenuMeter.app`
