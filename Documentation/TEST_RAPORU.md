# GMS Commander — Test Raporu

Tarih: 27 Ekim 2026 · Sürüm: 1.0.0 · Platform: macOS (Apple Silicon, arm64)

## 1. Özet

| Katman | Durum | Sonuç |
|---|---|---|
| Derleme (`swiftc`, 59 Swift kaynağı) | ✅ Çalıştırıldı | 0 hata |
| Bağımsız test koşucusu (`Tests/StandaloneTests`) | ✅ Çalıştırıldı | **390 doğrulama, 390 başarılı / 0 başarısız** |
| XCTest paketi (`Tests/GMSCommanderTests`) | ⚠️ Çalıştırılamadı | Xcode.app kurulu değil (bkz. §2) |
| Uygulama derleme + paketleme | ✅ Çalıştırıldı | `GMS Commander.app` (5,2 MB, arm64, ad-hoc imza) |
| Xcode projesi üretimi | ✅ Çalıştırıldı | 59 kaynak, 1 kaynak dosyası, 13 test dosyası |
| DMG oluşturma + doğrulama | ✅ Çalıştırıldı | `hdiutil verify`: checksum VALID (1,7 MB) |
| Çalışma zamanı dumanı testi | ✅ Çalıştırıldı | Pencere açıldı, çökme yok; ilk kurulumda macOS klasör izni istendi |
| Arayüz dili | ✅ Doğrulandı | Menü, paneller, durum çubuğu ve işlev tuşu şeridi Türkçe |
| Yeni pencerelerin UI dumanı testi | ✅ Çalıştırıldı | Gelişmiş arama, karşılaştırma, hash, desen seçimi, görüntüleyici, düzenleyici ve klavye profili açıldı (bkz. §5.4) |

## 2. Neden XCTest çalıştırılamadı?

Bu makinede yalnızca **Command Line Tools** kuruludur; `Xcode.app` yoktur. Bu nedenle:

- `xcodebuild` komutu bulunmuyor,
- XCTest çerçevesi SDK'da yok (`import XCTest` derlenemez),
- `xcodebuild test` ile `GMSCommanderTests` paketi koşturulamıyor.

Bu boşluğu kapatmak için testler **iki katmanlı** yazıldı:

1. `Tests/GMSCommanderTests/*.swift` — Xcode kurulu bir makinede `⌘U` veya
   `./Scripts/test.sh --xcode` ile çalışan standart XCTest paketi.
2. `Tests/StandaloneTests/main.swift` — aynı senaryoları kapsayan, Xcode gerektirmeyen
   çalıştırılabilir koşucu. Ürün kodunu doğrudan derler (`@main` hariç), kendi
   `expect`/`expectEqual`/`expectThrows` yardımcılarını kullanır ve başarısızlıkta `exit(1)` verir.

Aşağıdaki 390 doğrulamanın tamamı **gerçek dosya sistemi** üzerinde, geçici klasörlerde koşturuldu.

## 3. Bağımsız koşucu sonuçları

Komut: `./Scripts/test.sh` (çıktı: `build/standalone-tests`)

| Test grubu | Doğrulama | Kapsam |
|---|---:|---|
| Model: `FileItem` | 20 | Meta veri okuma, gizli dosya, klasör boyutu, sembolik bağ, sıralama ölçütleri, klasörler önce, kararlı sıralama, `DirectorySnapshot` |
| Servis: `FileManagerService` | 21 | Listeleme, gizli filtre, klasör çakışması, ad doğrulama, yeniden adlandırma, benzersiz ad, silme, kök klasör |
| Servis: `FileCopyService` | 10 | Dosya/klasör/bağ kopyalama, üzerine yazma, ilerleme, boyut tahmini, hatalar |
| Servis: `FileMoveService` | 4 | Taşıma, aynı konum reddi, eksik kaynak, klasör taşıma |
| Servis: `FileSearchService` | 13 | Alt klasör araması, Türkçe karakter duyarsızlığı, gizli dosya, sonuç sınırı, boş sorgu, normalizasyon |
| Servis: gelişmiş arama | 18 | Joker/düzenli ifade, uzantı, boyut, tarih, içerik, ikili atlama, hariç desen, alt klasör, iptal |
| Servis: SHA-256 | 6 | Bilinen vektörler (`abc`, boş dosya), parçalı büyük dosya, klasör atlama, eksik dosya, iptal |
| Servis: görüntüleyici | 16 | UTF-8/UTF-16 algılama, ikili algılama, kısaltmalı okuma, hex görünümü, atomik kaydetme, dış değişiklik, satır ofsetleri |
| Görünüm: `FileEditorViewModel` | 9 | Yükleme, değişiklik izleme, kaydetme, dış değişiklik uyarısı, ikili dosya reddi |
| Görünüm: gelişmiş arama modeli | 12 | Ad süzgeci, CSV, boş ölçüt, geçersiz regex/boyut/aralık, sıfırlama |
| Görünüm: hash modeli | 6 | Sonuç üretimi, klasör atlama, bilinen özet, CSV, tamamlanmış işlemde iptal |
| Görünüm: klasör karşılaştırma modeli | 9 | Sol/sağ/aynı sayıları, süzgeçler, CSV, aynı klasör hatası |
| Yardımcı: seçim deseni eşleştirme | 12 | Joker, tek karakter jokeri, alt dize, Türkçe katlama, regex, geçersiz desen, boş desen |
| Servis: klasör karşılaştırma | 20 | Aynı/farklı boyut/tür/içerik/tarih, alt klasör, gizli, salt okunur doğrulama, iç içe klasör, iptal |
| Model: `FileProperties` | 9 | Boyut/izin/tarih/tür, sembolik bağ hedefi, klasör toplam boyutu, eksik dosya |
| Yardımcılar: biçimlendiriciler | 22 | Boyut, izinler, tarih, hata metinleri, ilerleme oranı, çakışma politikası, transfer modu |
| ViewModel: `FavoritesViewModel` | 30 | Hızlı erişim ekleme/gruplama, uygulama algılama, Türkçe adlar, disk yenileme/temizleme |
| Servis: `SettingsStore` | 21 | Kalıcılık, panel yolları, sıralama, çakışma politikası, işlev tuşu atamaları ve çakışma reddi |
| Görünüm: `ThemeManager` | 7 | Tema/yazı boyutu kalıcılığı, görünüm imzası, boyut sınırı, açık/koyu tema |
| Gezinme: yol kırıntıları | 5 | Ev yolu kısaltması, kökten gösterim, bileşen hedefleri |
| Gezinme: yapıştırma hedefi | 4 | Etkin paneldeki öğeler karşı panele, dış kaynaklar etkin panele, karışık ve boş kaynak davranışı |
| ViewModel: `FilePanelViewModel` | 23 | Gezinme, geri/ileri, sıralama, seçim, yol gösterimi, gizli dosyalar |
| Servis: `ZipArchiveService` | 4 | Dosya/klasör sıkıştırma, boşluklu ad, arşiv doğrulama |
| Servis: `ArchiveService` | 22 | ZIP/TAR oluşturma ve çıkarma, path traversal koruması, sembolik bağ güvenliği, geçersiz arşiv |
| Servis: `TrashService` | 9 | Çöp Kutusu'na taşıma, listeleme, geri yükleme, boşaltma, gizli dosyalar |
| Servis: `BatchRenameService` | 13 | Desen, sıra numarası, uzantı, önizleme, çakışma denetimi |
| ViewModel: `FileOperationViewModel` | 10 | Oran hesabı, yüzde/bayt metni, başlık eşlemesi |
| Yardımcılar: `KeyboardShortcutManager` | 11 | Katalog tutarlılığı (36 kayıt), benzersiz kimlik, tuş eşlemeleri |
| Yardımcılar: İşlev tuşları | 20 | F1–F12 eşlemesi, NC varsayılanları, özel atama, çakışma sanitizasyonu, etiketler |
| Servisler: Terminal hedefi | 4 | Klasör/dosya yolu, olmayan yol, Terminal kurulu denetimi |
| **Toplam** | **390** | **390 başarılı / 0 başarısız** |

Koşucunun son satırları:

```
────────────────────────────────────────────────────────────
Geçen: 390   Başarısız: 0   Toplam: 390
Tüm testler başarılı.
```

## 4. Testlerin ortaya çıkardığı ve düzeltilen hatalar

| # | Hata | Belirti | Düzeltme |
|---|---|---|---|
| 1 | `FileManagerService.isRoot("/")` yanlış | Kök klasörde "üst klasör" mantığı çalışmıyordu | Standartlaştırılmış yol karşılaştırması ve `/` özel durumu |
| 2 | Türkçe arama katlaması | "istanbul" araması "İSTANBUL" dosyasını bulamıyordu | `en_US_POSIX` katlama + `ı → i` normalizasyonu |
| 3 | `DirectorySnapshot.item(at:)` | `/var` ↔ `/private/var` farkı seçimi bozuyordu | Standartlaştırılmış yolla ikinci deneme |
| 4 | Fare ile satır seçimi | Başka satıra tıklayınca seçim değişmiyordu | `List` yerine AppKit `NSTableView` tabanlı liste |
| 5 | Kısayol kataloğu testi | Yeni kısayollar eklendikçe beklenen sayı eskiyordu | Katalog 36 kayda göre güncellendi |
| 6 | Gelişmiş aramada uzantı/boyut/içerik süzgeçleri | Klasörler de sonuçlara katılıyordu | Dosyaya özgü ölçütlerde klasörler atlanıyor (`hasFileOnlyCriteria`) |
| 7 | Menü kısayolu çakışması | "Gelişmiş Ara" ⌘F'yi alıp "Ara"yı gölgeliyordu | Ara ⌘F, Gelişmiş Ara ⌥⌘F |
| 8 | `FolderCompareService.scan` | Kaçışlı closure `inout` sayaç yakalayamıyordu (derleme hatası) | Sayaç yerel değişkende; fonksiyon `(items, skipped)` döndürüyor |
| 9 | `FileHashSheet` zayıf yakalama | `[weak self]` uyarısı | Dış görevde güçlü yakalama, iç `@MainActor` görevde `self` |
| 10 | Karşılaştırma testi | `writeFile("alt/ic.txt", in: alt)` çift klasör üretiyordu | Yol düzeltildi, beklenen öğe sayısı güncellendi |
| 11 | Yardım ekranı etiketi | Klasör karşılaştırma ⌘K yazıyordu | ⌥⌘K yapıldı |
| 12 | CSV BOM testi | `String(contentsOf:)` BOM'u tüketiyordu | Test ham `Data` önekiyle denetleniyor |
| 13 | Gelişmiş arama iptali | `Task.isCancelled` detached görevde etkisizdi | `SearchCancellation` bayrağı eklendi |
| 14 | Arama sonucundan panele dönüş | Seçim yarış koşuluna takılıyordu | `pendingRevealURL` ile yeniden yükleme sonunda seçim |
| 15 | Desene göre seçim altlığı | 580 pt genişlikte beş düğme etiketi kırpılıyordu | Pencere 820×520'ye genişletildi |
| 16 | Önizleme bölmesi büyütülemiyordu | `HSplitView` ayırıcısı 1 pt olduğu için fareyle yakalanamıyordu | Bölme `HStack` + 9 pt tıklama alanlı tutamaçla kuruldu; `DragGesture` genişliği 170–900 pt arasında değiştiriyor |
| 17 | Tek tıklama klasöre giriyordu | Seçim yapmak isteyen kullanıcı yanlışlıkla klasörün içine giriyordu | Tek tıklama yalnızca seçer, giriş çift tıklamaya taşındı (`handleDoubleClick`) |
| 18 | Yol çubuğunda disk adı görünmüyordu | Ev klasörü "~" ile kısaltılıyor, adlar sağa kaçıp kırpılıyordu | Yol kırıntıları her zaman disk kökünden üretiliyor; ilk öğe disk adı, hizalama solda |
| 19 | Yol alanı odak alamıyordu | `⌘L` sonrası yazılan metin alana girmiyordu | AppKit `NSTextField` alt sınıfı; odak `viewDidMoveToWindow` içinde veriliyor |
| 20 | `⌘L` isteği kayboluyordu | Görünüm yeniden kurulurken yayınlanan durum sıfırlanıyordu | Yayınlanan durum yerine `NotificationCenter` bildirimi (`beginPathEditing`) |
| 21 | Yol alanında `⌘V` dosya yapıştırıyordu | Metin alanı yerine "Yapıştırılacak Öğe Yok" uyarısı çıkıyordu | İlk yanıtlayıcı `NSTextView` ise `⌘C/⌘X/⌘V/⌘A` standart metin eylemine yönlendiriliyor |
| 22 | İzin hatasında eski satırlar kalıyordu | Klasöre erişilemediğinde liste boşalmıyordu | `reload` hata dalında `rebuildItems()` ile liste ve sürüm birlikte yenileniyor |

## 5. Elle yapılan doğrulamalar

### 5.1 Derleme ve paketleme

```
$ ./Scripts/build.sh
==> GMS Commander 1.0.0 derleniyor
    59 Swift dosyası derleniyor (26.6.2 SDK: MacOSX.sdk)
==> Paket hazır: .../build/GMS Commander.app
Identifier=com.gms.commander
Format=app bundle with Mach-O thin (arm64)
    Boyut: 5.2M
```

```
$ ./Scripts/create_dmg.sh
==> DMG hazır: .../build/GMS_Commander_v1.0.0_mac_arm64.dmg
hdiutil: verify: checksum ... is VALID
    Boyut: 1.7M
```

`python3 Scripts/generate_xcodeproj.py` → 59 kaynak, 1 kaynak dosyası, 13 test dosyası.

### 5.2 Çalışma zamanı dumanı testi

```
$ open "build/GMS Commander.app"
$ osascript -e 'tell application "System Events" to get {name, position, size} of every window of process "GMS Commander"'
GMS Commander, 1728, 195, 1920, 1084
```

- Ana pencere açılışta `center()` ile ekranın ortasına yerleşiyor; iki panel `CenteringSplitView`
  sayesinde eşit (50/50) genişlikte başlıyor.

- Uygulama ikinci ekranda (1920×1200) tam boyutlu açıldı; ana pencere, iki panel,
  Hızlı Erişim kenar çubuğu, durum satırı ve F3–F11 şeridi görüntülendi.
- İlk çalıştırmada `~/Downloads` taranırken macOS **"İndirilenler klasöründeki dosyalara
  erişmek istiyor"** izin diyaloğu gösterdi. Bu, uygulama hatası değil, macOS TCC
  korumasıdır; otomasyon izni kullanıcı adına yanıtlamadı.
- `~/Library/Logs/DiagnosticReports` altında çökme raporu görülmedi.
- Uygulama `quit` AppleEvent'ine normal yanıt verdi.

### 5.3 Arayüz dili

Ekran görüntüsünde menü çubuğu (`Dosya`, `Düzen`, `Görünüm`, `Git`, `Araçlar`,
`Pencere`, `Yardım`), panel başlıkları (`Downloads`, `Documents`, `SOL`, `SAĞ`),
sütun başlıkları (`Ad`, `Tür`, `Boyut`, `Değiştirme Tarihi`), durum satırı ve
işlev tuşu şeridi (`F3 Görüntüle`, `F4 Düzenle`, `F5 Kopyala`, `F6 Taşı`,
`F7 Klasör`, `F8 Sil`, `F9 Terminal`, `F10 Çıkış`, `F11 Sıkıştır`) Türkçe doğrulandı.

### 5.4 Yeni pencerelerin UI dumanı testi

Test, gerçek ayarlara dokunmamak için ayrı paket kimliğiyle (`com.gms.commander.uitest`)
geçici bir kopya üzerinde yapıldı; test sonunda kopya ve ayarları silindi.

| Pencere | Açılış | Gözlem |
|---|---|---|
| Gelişmiş arama | `⌥⌘F` | Form alanları, "Dosyalar/Klasörler/Alt klasörler dahil" onayları, "Ara" düğmesi Türkçe göründü |
| Klasör karşılaştırma | `⌥⌘K` | "Karşılaştır" çalıştırıldı; "Aynı 1 · Farklı boyut 0 · Yalnızca solda 3 · Yalnızca sağda 1" özeti ve fark tablosu üretildi |
| SHA-256 | `⌥⌘H` | Seçili `ornek.txt` için 64 karakterlik özet hesaplandı; dosya seçilmezse "en az bir dosya seçin" uyarısı çıktı |
| Desene göre seçim | `⇧⌘A` | `*` deseni 3 öğeyi eşleştirdi, yürürlükteki seçim işaretlendi |
| Görüntüleyici | `F3` | `ornek.txt` UTF-8 olarak, satır numaralarıyla açıldı; Metin/Hex sekmeleri göründü |
| Düzenleyici | `F4` | İçerik ve satır numaraları yüklendi; "27 karakter · 3 satır", Kaydet düğmesi etkin |
| Klavye profili | `⌘,` → Davranış | F3–F12 atama listesi ve "İşlev tuşlarını F1–F12 arasında değiştirin" açıklaması göründü |

Not: Görüntülerde görünen "İndirilenler klasörüne erişim" diyaloğu, `CGWindowList`
ile yapılan denetimde **UserNotificationCenter** tarafından sunulan bir macOS TCC
istemi olarak belirlendi; uygulamanın kendi penceresi değildir ve test sırasında
kullanıcı adına yanıtlanmadı.

### 5.5 Sürükle-bırak, yol çubuğu ve önizleme doğrulamaları (27 Ekim 2026)

Sentetik fare/klavye olayları (`CGEvent` + `screencapture`) ile yapılan canlı doğrulamalar:

| Davranış | Yöntem | Sonuç |
|---|---|---|
| Paneller arası sürükleme | Sol panelden `deneme.txt` sağ panel klasörüne sürüklendi | ✅ Dosya hedef klasöre taşındı (`ls` ile doğrulandı) |
| Çoklu seçim + ⌘C/⌘V | `a.txt`, `b.txt`, `altKlasor` (içindeki `c.txt` ile) seçilip kopyalandı | ✅ Üç öğe hedefe kopyalandı; durum çubuğu "3 öğe seçili" gösterdi |
| Yol alanı odağı | `⌘L` sonrası alana yazı yazıldı | ✅ Alan odaklandı ve yazılan karakter alana girdi |
| Yol çubuğu yerleşimi | Ekran görüntüsü | ✅ Disk simgesinin hemen yanında "Macintosh HD / Users / macpro" biçiminde sol hizalı; disk adı görünüyor |
| Yol kırıntısına tıklama | Yol çubuğundaki "Macintosh HD" kırıntısına tıklandı | ✅ Panel kök klasöre geçti, liste kök içeriğini gösterdi |
| Klasöre çift tıklama | "Users" satırına çift tıklandı | ✅ Panel `/Users` klasörüne girdi |
| Klasöre tek tıklama | "Shared" satırına tek tıklandı | ✅ Yol değişmedi; tek tıklama klasöre girmiyor |
| Önizleme bölmesi | Her iki panelde bölme açıldı | ✅ Liste + "ÖNİZLEME" bölmesi görüntülendi |
| Önizleme genişliği | Bölmenin sol kenarındaki tutamaç fareyle 150 pt sola sürüklendi | ✅ Önizleme bölmesi büyüdü (240 → 317 pt) |
| Panel genişlikleri | Ekran görüntüsü | ✅ Sol ve sağ panel eşit genişlikte |

Sentetik olay iletiminin bu makinede güvenilir olmaması nedeniyle **canlı doğrulanamayan**
(gerçek fare/klavye ile kullanıcı testi gerektiren) davranışlar:

- F3 görüntüleyici penceresinin (sheet) kenarından yeniden boyutlandırılması,
- Yol alanına elle yol yazıp Enter ile gezinmenin uçtan uca denenmesi (odak ve yazma
  doğrulandı; Enter sonrası gezinme yalnızca kod düzeyinde doğru),
- Seçili dosyaların Finder penceresine sürüklenmesi (paneller arası sürükleme doğrulandı;
  pano `.fileURL` olarak yayınlandığı için Finder hedefi kod düzeyinde destekli).

## 6. Kapsanmayan alanlar (bilinen eksikler)

| Alan | Neden | Öneri |
|---|---|---|
| Kalıcı UI otomasyonu | XCUITest hedefi yok | Xcode 15+ ile tekrar edilebilir UI testleri eklenebilir |
| XCTest paketinin koşturulması | Xcode.app yok | Xcode kurulu makinede `./Scripts/test.sh --xcode` |
| XCUITest | Xcode ve UI test hedefi gerekir | Xcode 15+ ile hedef eklenebilir |
| VoiceOver / tam erişilebilirlik | Ekran okuyucu otomasyonu yapılmadı | VoiceOver ile panel, diyalog ve yeni pencereler denenmeli |
| Çok büyük klasörlerde performans | Ölçüm yapılmadı | 100k+ öğeli klasörde ölçüm ve gerekirse sanallaştırma |
| Ağ birimleri / APFS anlık görüntüleri | Ortamda ağ birimi yok | Elle test edilmeli |
| İngilizce yerelleştirme | Şartname Türkçe arayüz istiyor | Gerekirse `en.lproj` eklenmeli |
| Simge ızgarasında sürükle-bırak | Sürükleme/kopyalama yalnızca liste görünümünde | Izgara görünümü için `NSCollectionView` sürükleme desteği eklenmeli |
| Klasör senkronizasyonu / kuru çalıştırma | P2 kapsamında henüz yok | Karşılaştırma raporundan sonra planlanmalı |
| Noter onayı ve Gatekeeper | Developer ID sertifikası yok | Dağıtımda `notarytool` gerekir |

## 7. Yeniden üretme

```bash
./Scripts/clean.sh
./Scripts/test.sh          # 390/390
./Scripts/build.sh         # build/GMS Commander.app
python3 Scripts/generate_xcodeproj.py
./Scripts/create_dmg.sh    # build/GMS_Commander_v1.0.0_mac_arm64.dmg (doğrulanır)
```
