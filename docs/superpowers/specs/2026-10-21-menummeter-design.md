# MenuMeter — Tasarım Belgesi (Spec)

- **Tarih:** 2026-10-21
- **Durum:** Onaylandı
- **Kapsam:** macOS menü çubuğunda CPU, RAM, ağ hızı, SSD doluluğu ve GPU kullanımını gösteren; tıklanınca Activity Monitor'ü açan hafif yerel uygulama

---

## 1. Amaç ve Kapsam

### 1.1 Amaç

macOS menü çubuğunda kompakt bir ikon ve sırayla dönen tek bir metrikle sistem durumunu gösteren, sol tıklandığında Activity Monitor'ü öne getiren, arka planda minimum kaynak tüketen yerel bir uygulama (`MenuMeter`) geliştirmek.

### 1.2 Hedefler

- Menü çubuğunda CPU, RAM, ağ indirme/yükleme hızı, SSD doluluk yüzdesi ve GPU kullanımını göstermek.
- Metrikleri 3 saniyede bir döndürmek: CPU → RAM → Ağ → SSD → GPU.
- Sol tıkta Activity Monitor'ü açmak; sağ tıkta ayrıntılı değerler, başlangıçta açma ve çıkış menüsü sunmak.
- Xcode gerektirmeden, mevcut Command Line Tools + SwiftPM ile derlenebilmek.
- Ortalama CPU tüketimi <%0,2 ve bellek tüketimi <20 MB olmak.

### 1.3 Kapsam Dışı (Non-Goals)

- Dock simgesi veya Dock tile gösterimi (mevcut `DockMeter` projesinin kapsamıdır; bu projeye dokunulmaz).
- Pencere, tercihler ekranı veya grafiksel geçmiş/grafik çizimi.
- Üçüncü parti bağımlılıklar, `powermetrics`, root/sudo, erişilebilirlik veya ekran kaydı izinleri.
- Kullanıcı tarafından değiştirilebilir yenileme aralığı; aralık sabit 3 saniyedir.

---

## 2. Mimari ve Bileşenler

Uygulama AppKit tabanlıdır ve `LSUIElement` olarak çalışır; Dock'ta görünmez, pencere açmaz.

```
MenuMeter.app (LSUIElement, Dock'ta görünmez)
┌───────────────────────────────────────────────────────────┐
│ AppDelegate                                               │
│   ├── StatusItemController  → NSStatusItem (ikon + metin) │
│   │      ├── sol tık → Activity Monitor                   │
│   │      └── sağ tık → menü                               │
│   └── MetricsEngine (3 sn DispatchSourceTimer, utility)   │
│          ├── CPUSampler      (Mach host_processor_info)   │
│          ├── MemorySampler   (host_statistics64)          │
│          ├── NetworkSampler  (sysctl NET_RT_IFLIST2)      │
│          ├── DiskSampler     (statfs "/")                 │
│          └── GPUSampler      (IOKit IOAccelerator)        │
└───────────────────────────────────────────────────────────┘
```

### 2.1 Katmanlar

#### `MenuMeterCore` (kütüphane)

AppKit'ten bağımsız, test edilebilir çekirdek:

- **`MetricsSnapshot`** (`struct`, `Equatable`, `Sendable`):
  - `cpu: Double` (0.0–1.0)
  - `ramUsed: UInt64`, `ramTotal: UInt64` (bayt)
  - `networkDown: Double`, `networkUp: Double` (bayt/sn)
  - `diskUsed: UInt64`, `diskTotal: UInt64` (bayt)
  - `gpu: Double?` (0.0–1.0; veri yoksa `nil`)
  - `timestamp: Date`
  - Hesaplanan: `ramFraction`, `diskFraction` (0.0–1.0, clamp'li)

- **Sampler'lar**: her biri durum tutan, `sample()` çağrısıyla güncel değer döndüren sınıflar.
  - `CPUSampler.sample() -> Double` — ilk çağrıda `0.0`, sonraki çağrılarda tik farkı oranı.
  - `MemorySampler.sample() -> (used: UInt64, total: UInt64)`
  - `NetworkSampler.sample() -> (down: Double, up: Double)` — ilk çağrıda `(0, 0)`, sonraki çağrılarda bayt/sn.
  - `DiskSampler.sample() -> (used: UInt64, total: UInt64)?` — okunamazsa `nil`.
  - `GPUSampler.sample() -> Double?` — veri yoksa `nil`.

- **`MetricsEngine`**: enjekte edilen sampler'larla tek `DispatchSourceTimer` üzerinden 3 sn'de bir örnek alır; sonucu ana kuyruğa `@Sendable` callback ile iletir. `start(onUpdate:)`, `stop()`, `sampleNow()` arayüzleri. `deinit`/`stop` timer'ı iptal eder.

- **`Metric`** (`enum`, `CaseIterable`): `cpu`, `ram`, `network`, `disk`, `gpu`; sabit sıra. `MetricRotation.next(after:)` bir sonraki metriği döndürür (sondan başa döner).

- **`StatusTextFormatter`**: `Metric` + `MetricsSnapshot` → menü çubuğu metni. Saf fonksiyonlar; test edilebilir.

- **`ByteFormatter`**: bayt/sn ve bayt değerlerini `B`, `K`, `M`, `G` (1024 tabanı, tek ondalık) biçimine çevirir.

#### `MenuMeter` (çalıştırılabilir)

- **`main.swift`**: `NSApplication.shared`, delegate ataması, `.accessory` etkinleştirme politikası, `app.run()`.
- **`AppDelegate`**:
  - `applicationDidFinishLaunching`: `StatusItemController` ve `MetricsEngine`'i kurar, timer'ı başlatır.
  - `NSWorkspace.willSleepNotification` / `screensDidSleepNotification`: timer'ı durdurur.
  - `didWakeNotification` / `screensDidWakeNotification`: hemen bir örnek alır ve timer'ı yeniden başlatır.
  - Activity Monitor yolu ve açma yardımcıları.
- **`StatusItemController`**:
  - `NSStatusItem` (variable length), ikon + `attributedTitle`.
  - Sol tık: Activity Monitor'ü açar. Sağ tık: menüyü gösterir.
  - Her güncellemede metni, ikonu ve `accessibilityLabel`'i yeniler; yalnızca değer değiştiyse çizer.
- **`StatusIconRenderer`**:
  - 18×18 template `NSImage` üretir.
  - CPU/RAM/SSD/GPU için dairesel doluluk halkası; ağ için küçük ↓↑ oku.
  - Template olduğundan açık/koyu menü çubuğuna otomatik uyum sağlar.
- **`LoginItemController`**:
  - `SMAppService.mainApp` ile `Başlangıçta Aç` durumunu okur, kaydeder/kaldırır.
  - Hata durumunda durumu geri alır ve tek seferlik `NSAlert` gösterir.
- **`MenuBuilder`**: sağ tık menüsünü kurar.

### 2.2 Veri Akışı

1. Timer her 3 saniyede bir tetiklenir (utility kuyruğu).
2. Beş sampler sırayla çağrılır, `MetricsSnapshot` üretilir.
3. Snapshot ana kuyruğa iletilir.
4. `MetricRotation` sıradaki metriği seçer.
5. `StatusTextFormatter` metni, `StatusIconRenderer` ikonu üretir; `NSStatusItem` güncellenir.
6. Sağ tık menüsündeki ayrıntı satırları aynı snapshot'tan beslenir.

---

## 3. Metrikler ve Gösterim

| Metrik | Kaynak / formül | Menü çubuğu |
|---|---|---|
| CPU | `host_processor_info`: (Δuser + Δsystem + Δnice) / Δtotal | `CPU 12%` |
| RAM | `host_statistics64`: (active + wired + compressed + speculative) × sayfa boyutu / `hw.memsize` | `RAM 9.8G` |
| Ağ | `sysctl(NET_RT_IFLIST2)` rx/tx bayt farkı; `lo0`, `utun*`, `awdl*`, `llw*`, `bridge*` hariç | `Ağ ↓1.2M ↑0.4M` |
| SSD | `statfs("/")`: (blocks − bfree) × bsize / (blocks × bsize) | `SSD 42%` |
| GPU | IOKit `IOAccelerator` → `Device Utilization %`, yoksa `Renderer Utilization %`, yoksa `GPU Core Utilization` | `GPU 8%` / `GPU —` |

### 3.1 Kurallar

- Sıra: **CPU → RAM → Ağ → SSD → GPU**; her 3 saniyede sonraki metrik.
- İlk ölçümde CPU ve ağ `0` gösterir (delta tabanı yoktur).
- CPU, RAM, SSD, GPU değerleri `0.0...1.0` aralığına clamp edilir; yüzdeler tam sayıya yuvarlanır.
- RAM menü çubuğunda kullanılan miktar (GB, tek ondalık); SSD yüzde olarak gösterilir.
- Ağ birimleri otomatik ölçeklenir: `B/s`, `K/s`, `M/s`, `G/s` (1024 tabanı, tek ondalık).
- GPU değeri `0.0...1.0` dışında gelirse yüzde kabul edilip 100'e bölünür; aralık dışı clamp edilir.
- Sağ tık menüsünün üstünde pasif satırlar:
  - `CPU 12%`
  - `RAM 9.8 / 16.0 GB`
  - `Ağ ↓1.2M/s ↑0.4M/s`
  - `SSD 42% (boş 268.0 GB)`
  - `GPU 8%` veya `GPU kullanılamıyor`

### 3.2 Biçimlendirme

- Menü çubuğu yazı tipi: 11 pt, monospaced digit (değer değişiminde genişlik zıplamasını önler).
- Metin rengi: `labelColor` (menü çubuğu görünümüyle uyumlu).
- Biçimlendirme saf fonksiyonlarda; yerelleştirme kapsam dışı (Türkçe sabit metinler).

---

## 4. Arayüz ve Etkileşim

### 4.1 Menü Çubuğu Öğesi

- `NSStatusItem` değişken uzunlukta; ikon + metin.
- İkon 18×18 pt template; o anki metrik yüzdesini halka dolgusu olarak gösterir. Ağ metriğinde ↓↑ sembolü kullanılır.
- Sol tıklama Activity Monitor'ü açar; sağ tıklama menüyü açar.
- Menü öğesinin erişilebilirlik etiketi her metrik değişiminde güncellenir (ör. "CPU kullanımı yüzde 12").

### 4.2 Sağ Tık Menüsü

1. Pasif ayrıntı satırları (beş metrik).
2. Ayırıcı.
3. `Etkinlik Monitörü'nü Aç`
4. `Başlangıçta Aç` (işaretli; `SMAppService.mainApp`)
5. Ayırıcı.
6. `Çıkış` (⌘Q)

### 4.3 Activity Monitor

- Öncelikli yol: `/System/Applications/Utilities/Activity Monitor.app`
- `NSWorkspace.shared.openApplication(at:configuration:)` ile etkinleştirilerek açılır; yeni pencere açılmaz.
- Yol yoksa `/Applications/Utilities/Activity Monitor.app` denenir.
- Her iki yol da yoksa hata loglanır; uygulama çalışmaya devam eder.

---

## 5. Kaynak Tüketimi ve Hata Yönetimi

### 5.1 Kaynak Stratejisi

- Tek `DispatchSourceTimer`, 3 sn aralık, utility kalite seviyesi.
- Alt süreç yok (`top`, `ps`, `powermetrics`, `netstat` yok).
- Mach/sysctl tamponları yeniden kullanılır; `host_processor_info` tahsisi `vm_deallocate` ile serbest bırakılır.
- IOKit GPU servisi bir kez açılır ve önbelleklenir.
- Yalnızca metin/ikon değeri değiştiğinde çizim yapılır; animasyon yok.
- Uyku ve ekran kilidi sırasında timer durur.
- Hedef: ortalama <%0,2 CPU, <20 MB RSS.

### 5.2 Hata Durumları

| Durum | Davranış |
|---|---|
| GPU istatistiği okunamıyor | `GPU —`; konsola bir kez uyarı |
| Mach CPU/RAM çağrısı başarısız | Önceki değer korunur, sonraki turda yeniden denenir |
| Ağ sayacı sıfırlanması/taşması | Negatif fark `0`'a kırpılır |
| `statfs` başarısız | `SSD —` |
| Activity Monitor bulunamıyor | Alternatif yol, sonra sessiz log |
| Başlangıçta açma kaydı başarısız | İşaret geri alınır, tek seferlik uyarı gösterilir |
| İlk ölçüm | CPU ve ağ `0`; uygulama çökmez |
| Sistem uykusu | Timer durur; uyanınca hemen örnek alınır |

---

## 6. Proje Yapısı ve Paketleme

### 6.1 Proje Yapısı

```
~/Projects/MenuMeter/
├── Package.swift
├── Sources/
│   ├── MenuMeterCore/
│   │   ├── Models/
│   │   │   ├── MetricsSnapshot.swift
│   │   │   └── Metric.swift
│   │   ├── Formatting/
│   │   │   ├── ByteFormatter.swift
│   │   │   └── StatusTextFormatter.swift
│   │   ├── Samplers/
│   │   │   ├── CPUSampler.swift
│   │   │   ├── MemorySampler.swift
│   │   │   ├── NetworkSampler.swift
│   │   │   ├── DiskSampler.swift
│   │   │   └── GPUSampler.swift
│   │   └── Services/
│   │       └── MetricsEngine.swift
│   └── MenuMeter/
│       ├── main.swift
│       ├── AppDelegate.swift
│       ├── StatusItemController.swift
│       ├── StatusIconRenderer.swift
│       ├── LoginItemController.swift
│       └── MenuBuilder.swift
├── Tests/
│   └── MenuMeterCoreTests/
│       ├── CPUSamplerTests.swift
│       ├── MemorySamplerTests.swift
│       ├── NetworkSamplerTests.swift
│       ├── DiskSamplerTests.swift
│       ├── GPUSamplerTests.swift
│       ├── MetricRotationTests.swift
│       └── FormatterTests.swift
├── Resources/
│   └── Info.plist
├── scripts/
│   └── build_app.sh
├── README.md
└── docs/
    └── superpowers/specs/2026-10-21-menummeter-design.md
```

### 6.2 Paketleme

`scripts/build_app.sh`:

1. `swift build -c release`
2. `MenuMeter.app/Contents/{MacOS,Resources}` oluşturur.
3. `Info.plist` kopyalar: `CFBundleIdentifier=com.cem.MenuMeter`, `CFBundleName=MenuMeter`, `CFBundlePackageType=APPL`, `LSUIElement=true`, `NSHighResolutionCapable=true`, `LSMinimumSystemVersion=13.0`.
4. Release binary'sini `Contents/MacOS/MenuMeter` olarak kopyalar.
5. `codesign -s - --force --deep MenuMeter.app` ile ad-hoc imzalar.
6. `~/Applications/MenuMeter.app` konumuna kurar (varsa eskisini değiştirir).

Kaldırma: uygulamayı kapatıp `~/Applications/MenuMeter.app` dizinini silmek; başlangıçta açma kaydı menüden kaldırılmalıdır.

---

## 7. Test ve Doğrulama Planı

### 7.1 Otomatik Testler (`swift test`)

- **CPUSamplerTests**: ilk örnek `0`; normal delta hesabı; sıfır toplamda `0`; taşma/negatif delta koruması; clamp.
- **MemorySamplerTests**: normal kullanım oranı; %100 üzeri clamp; sıfır toplam koruması.
- **NetworkSamplerTests**: bayt farkı → hız; sayaç sıfırlanmasında negatif farkın `0` olması; ilk örnek `(0, 0)`.
- **DiskSamplerTests**: doluluk oranı; sıfır toplam koruması; clamp.
- **GPUSamplerTests**: `Device Utilization %` ve `Renderer Utilization %` ayrıştırma; eksik sözlükte `nil`; 0–1 ve 0–100 girdilerinin normalize edilmesi.
- **MetricRotationTests**: sıra ve başa dönüş.
- **FormatterTests**: `CPU 12%`, `RAM 9.8G`, `Ağ ↓1.2M ↑0.4M`, `SSD 42%`, `GPU —`; bayt birim eşikleri.

### 7.2 Manuel Doğrulama

1. `swift test` ve `swift build` hatasız.
2. `scripts/build_app.sh` → `~/Applications/MenuMeter.app`, `codesign -vvv` başarılı.
3. Uygulama açıldığında menü çubuğunda ikon + metin görünür, Dock'ta simge yoktur.
4. Metrik 3 saniyede bir döner ve değerler Makineyle uyumludur.
5. Sol tık Activity Monitor'ü açar; sağ tık menüsü doğru çalışır.
6. `Başlangıçta Aç` oturum kapatıp açıldığında uygulamayı başlatır.
7. Uyku/uyanma sonrası ölçüm devam eder.
8. `yes > /dev/null` çalışırken CPU değeri belirgin artar; `killall yes` sonrası düşer.
9. Activity Monitor'de `MenuMeter` için CPU <%0,5 ve RSS <25 MB.
10. GPU desteklenmiyorsa `GPU —` görünür ve uygulama kararlı kalır.

---

## 8. Global Kısıtlar

- Yalnızca Apple yerel framework'leri: AppKit, Foundation, IOKit, ServiceManagement, Darwin, CoreGraphics.
- Üçüncü parti paket yok.
- Full Xcode gerekmez; mevcut Command Line Tools ve Swift 6.4 ile derlenir.
- macOS 13 ve üzeri hedeflenir (SMAppService için).
- Menü çubuğu metinleri Türkçe ve sabittir.
