# GMS Commander

İki panelli (dual-pane), klavye odaklı, tamamen Türkçe bir macOS dosya yöneticisi.
fman'ın kullanım kolaylığından ilham alır; SwiftUI + AppKit ile sıfırdan yazılmıştır.

| | |
|---|---|
| Sürüm | 1.0.0 |
| Paket kimliği | `com.gms.commander` |
| Minimum sistem | macOS 14.0 (Sonoma) |
| Mimari | Apple Silicon (arm64) |
| Arayüz dili | Türkçe (tüm metinler `tr.lproj/Localizable.strings`) |
| Teknoloji | Swift 5 dili, SwiftUI + AppKit, FSEvents, Quick Look |

---

## Özellikler

**Paneller**
- İki bağımsız panel; her biri kendi klasörü, seçimi, sıralaması ve gezinme geçmişiyle çalışır.
- Aktif panel başlık rengiyle belirginleşir; `Tab` ile panel değiştirilir.
- Panel genişlikleri sürüklenerek ayarlanır, pencere yeniden boyutlandırıldığında uyum sağlar.
- Altı seçilebilir tema (Norton Commander, Void Commander, Grafit, Gündüz, Solarized Dark, Yüksek Kontrast), ayarlanabilir arayüz yazı boyutu ve SF Symbols dosya simgeleri.

**Gezinme**
- Klasör listesinde en üstteki `..` satırına tıklayarak üst klasöre çıkma; geri/ileri gezinme (panel başına geçmiş).
- Üst yol çubuğundaki her klasör adına tıklayarak o konuma gitme; isteğe bağlı yol girişi ve yol kopyalama.
- Her panelin başlığından bağlı disk seçme; yolu elle yazma veya panoya kopyalanmış yolu yapıştırma.
- İki panelin ayırıcısına çift tıklayarak sol ve sağ paneli eşit genişliğe getirme.
- Üst araç çubuğundaki Yenile ile artık bağlı olmayan diskleri Diskler bölümünden temizleme ve bağlı birimleri yeniden tarama.
- Son kullanılan klasörler ayarlarda saklanır ve uygulama aynı yerden açılır.

**Dosya işlemleri**
- Kopyala / kes / yapıştır, paneller arası `F5` ile kopyalama, `F6` ile taşıma.
- Yeniden adlandırma, yeni klasör oluşturma, Çöp Kutusu'na taşıma, kalıcı silme (onaylı).
- Uzun işlemler arka planda yürür; ilerleme çubuğu, işlem türü, geçerli öğe, yüzde ve bayt bilgisi gösterilir, işlem iptal edilebilir.
- Çakışmalarda "Üzerine yaz / Atla / Yeniden adlandır / Tümüne uygula" seçenekleri.
- Sembolik bağlantı, paket (bundle) klasörü, izin ve erişim hataları güvenli biçimde ele alınır; hatalar Türkçe gösterilir.

**Görünüm ve yardımcılar**
- Ad, tür, boyut, değiştirilme tarihi sütunları; sütun başlığına tıklayarak sıralama.
- Gizli dosyaları gösterme/gizleme, klasörleri önce listeleme.
- Quick Look önizlemesi (`Space`, `⌘Y`), varsayılan uygulamayla açma, "Finder'da Göster".
- Dosya özellikleri (boyut, izinler, tarihler, tür, sembolik bağ hedefi, klasör toplam boyutu).
- Arama: alt klasörler dahil, Türkçe karakter duyarsız (`ı/i`, `ş/s`, `ğ/g`…), 2000 sonuç sınırı.
- Gelişmiş arama (`⌥⌘F`): ad/joker/düzenli ifade, uzantı, boyut, tarih, içerik ve hariç tutma ölçütleri; 5.000 sonuç sınırı, iptal ve CSV dışa aktarma.
- Gelişmiş arama sonuçlarından öğeyi panelde gösterme, açma ve yol kopyalama.
- Görüntüleyici (`F3`): metin/kod, ikili dosyalarda hex görünümü, kodlama algılama; resim ve PDF için sistem önizlemesi.
- Düzenleyici (`F4`): metin düzenleme, atomik kaydetme, dış değişiklik uyarısı ve üzerine yazma onayı.
- İki klasörü ad, boyut, tarih ve isteğe bağlı SHA-256 içeriğine göre karşılaştırma (`⌥⌘K`); salt okunur rapor, süzgeçler ve CSV dışa aktarma.
- SHA-256 özeti hesaplama (`⌥⌘H`): parçalı okuma, iptal, panoya kopyalama ve CSV.
- Desene göre seçim (`⇧⌘A`): joker/düzenli ifade, canlı önizleme, seçime ekleme/çıkarma, ters çevirme.
- Çöp Kutusu'nu görüntüleme, seçili öğeleri geri yükleme ve boşaltma.
- Klavye profili: F1–F12 işlev tuşlarını eylem başına yeniden atama, çakışma denetimi ve kalıcılık.
- FSEvents ile otomatik yenileme (ayarlardan kapatılabilir).
- Git durumu: dal adı ve değişiklik sayısı, depoyu Finder'da açma, dal adını kopyalama.
- Türkçe klavye kısayolları yardım ekranı.

**Hızlı erişim**
- Finder benzeri sol kenar çubuğunda dosya ve klasörleri hızlı erişime ekleme.
- Özel isimli/renkli bölümler oluşturma, yeniden sıralama, yeniden adlandırma ve silme; kayıtları bölümler arasında taşıma.
- Dosya/klasöre sağ tıklayıp hızlı erişime ekleme; klasörler Hızlı Erişim'e, `.app` uygulamaları Uygulamalar'a eklenir ve uygulamalar doğrudan başlatılır. Kayıtlı öğeler kendi bağlam menüsünden kaldırılabilir.
- Bağlı diskleri Diskler bölümünde gösterme; standart macOS klasör adlarını Türkçe görüntüleme.
- Kenar çubuğu, uygulama temasından bağımsız olarak macOS'un yerel Finder benzeri görünümünü kullanır.
- Hızlı erişim öğesinin görünen adını düzenleme ve bölüm içinde sıralama.

**Norton Commander düzeni**
- Seçilebilir altı tema (Norton Commander, Void Commander, Grafit, Gündüz, Solarized Dark, Yüksek Kontrast); monospaced hizalı sütunlar, etkin panelde belirgin çerçeve ve `SOL`/`SAĞ` rozeti.
- Pencere altında `F3`–`F11` işlev tuşu şeridi; tıklanabilir düğmeler ve etkin panel ipucu.
- `F11` ile seçili dosya ve klasörleri ZIP arşivine sıkıştırma.
- `F8` ile Çöp Kutusu'na taşımadan önce onay isteme.
- Fare ile tek tıklama seçimi her zaman değiştirir, çift tıklama açar, boş alana tıklama seçimi temizler.
- Sağ tık menüsünde **Yeni Klasör** ve **Terminal'de Aç** (geçerli klasörde yeni Terminal penceresi).

---

## Klavye kısayolları

| Kısayol | İşlev | | Kısayol | İşlev |
|---|---|---|---|---|
| `⌘C` | Kopyala | | `⌘⇧N` | Yeni klasör |
| `⌘X` | Kes | | `⌘R` | Yenile |
| `⌘V` | Yapıştır | | `⌘F` | Ara |
| `⌘A` | Tümünü seç | | `⌘I` | Özellikler |
| `⌘O` / `Return` | Aç | | `⌘Y` / `Space` | Quick Look |
| `⌘↑` / `Backspace` | Üst klasör | | `⌘[` / `⌘]` | Geri / İleri |
| `⌘⌫` | Çöp Kutusu'na taşı | | `⌥⌘⌫` | Kalıcı sil |
| `Tab` | Aktif paneli değiştir | | `⌘⇧.` | Gizli dosyalar |
| `F3` | Görüntüle (yerleşik görüntüleyici) | | `F4` | Düzenle (metin düzenleyici) |
| `F5` | Diğer panele kopyala | | `F6` | Diğer panele taşı |
| `F7` | Yeni klasör | | `F8` | Çöp Kutusu'na taşı |
| `F9` | Terminal'de aç | | `F10` | Çıkış |
| `F11` | Seçilenleri ZIP olarak sıkıştır | | `⌥⌘F` | Gelişmiş ara |
| `⌥⌘K` | Klasörleri karşılaştır | | `⌥⌘H` | SHA-256 hesapla |
| `⇧⌘A` | Desene göre seç | | `⇧⌘I` | Seçimi ters çevir |
| ``⌃` `` | Terminal'de aç | | `⌘⇧G` | Git durumunu yenile |
| `⌘/` | Kısayollar yardımı | | | |

---

## Gereksinimler

- macOS 14.0 veya üzeri, Apple Silicon Mac.
- **Uygulamayı çalıştırmak için:** ek bir şey gerekmez — `build/GMS Commander.app` ya da DMG yeterlidir.
- **Kaynaktan derlemek için:** Xcode Command Line Tools (`xcode-select --install`). Tam Xcode 15+ yalnızca
  `xcodebuild`/XCTest ile derlemek isteyenler için gereklidir.
- **Xcode projesini yeniden üretmek için:** Python 3 (standart kütüphane yeterli).

---

## Kurulum (DMG)

1. `build/GMS_Commander_v1.0.0_mac_arm64.dmg` dosyasını açın.
2. "GMS Commander" uygulamasını `Applications` klasörüne sürükleyin.
3. İlk açılışta Gatekeeper uyarısı görürseniz: **Sistem Ayarları → Gizlilik ve Güvenlik → "Yine de Aç"**.
   (Uygulama ad-hoc imzalıdır; noter onayı yapılmamıştır.)

---

## Derleme

```bash
./Scripts/build.sh          # build/GMS Commander.app üretir
```

Betik sırasıyla: tüm Swift kaynaklarını `swiftc` ile derler, `.app` paketini kurar, `Info.plist`
değişkenlerini (`$(PRODUCT_NAME)` vb.) doldurur, `tr.lproj` dizinini ve `AppIcon.icns` dosyasını
kopyalar, ardından ad-hoc imza atar.

```bash
./Scripts/create_dmg.sh     # build/GMS_Commander_v1.0.0_mac_arm64.dmg üretir + doğrular
./Scripts/clean.sh          # build/, DerivedData/, .DS_Store artıklarını siler
```

## Test

```bash
./Scripts/test.sh           # bağımsız test koşucusu (Xcode gerekmez)
./Scripts/test.sh --xcode   # Xcode varsa xcodebuild test ile XCTest paketini çalıştırır
```

Sonuç: **386 doğrulama, 386 başarılı** (ayrıntı: [Documentation/TEST_RAPORU.md](Documentation/TEST_RAPORU.md)).

## Xcode projesi

`GMS_Commander.xcodeproj` depoda hazırdır. Yeni dosya ekledikten sonra yeniden üretmek için:

```bash
python3 Scripts/generate_xcodeproj.py
```

Xcode'da açmak için: `open GMS_Commander.xcodeproj` → şema **GMS_Commander** → `⌘R`.

VS Code ile geliştirme akışı için: [Documentation/GELISTIRME.md](Documentation/GELISTIRME.md).

---

## Proje düzeni

```
GMS_Commander/
├── App/            Uygulama girişi ve menüler
├── Models/         FileItem, DirectorySnapshot, FileOperation, FileProperties
├── Services/       Dosya sistemi, kopyalama/taşıma, arama, hash, karşılaştırma, izleme, ayarlar, Git, Quick Look
├── ViewModels/     FilePanelViewModel, MainViewModel, FileOperationViewModel
├── Views/          Panel, AppKit tablo listesi, pencere, iletişim kutuları, ayarlar
├── Utilities/      Biçimlendiriciler, hata mesajları, yerelleştirme, kısayol kataloğu
└── Resources/      Info.plist, tr.lproj, Assets.xcassets
Tests/
├── GMSCommanderTests/   XCTest paketi (Xcode ile çalışır)
└── StandaloneTests/     Xcode gerektirmeyen koşucu (386 doğrulama)
Scripts/            build, test, clean, DMG, ikon ve proje üretici betikleri
Documentation/      MIMARI, GELISTIRME, TEST_RAPORU
```

Mimari ve veri akışı: [Documentation/MIMARI.md](Documentation/MIMARI.md)

---

## Bilinen sınırlar

- **XCTest çalıştırılamadı:** Bu makinede Xcode.app kurulu değil; `xcodebuild test` ve XCTest paketi
  koşturulamıyor. Bu nedenle testler, aynı senaryoları kapsayan `Tests/StandaloneTests` koşucusuyla
  doğrulandı. Xcode kurulu bir makinede `./Scripts/test.sh --xcode` tüm paketi çalıştırır.
- **İmzalama:** Ad-hoc imza (`codesign -s -`). Noter onayı ve Developer ID imzası yoktur.
- **App Sandbox kapalı:** Dosya yöneticisinin tüm diske erişebilmesi için bilinçli tercih.
- **Arama sınırı:** Hızlı aramada en fazla 2000, gelişmiş aramada 5000 sonuç; çok büyük ağaçlarda erken durur.
- **Git entegrasyonu** `/usr/bin/git` varlığına bağlıdır; yoksa özellik sessizce devre dışı kalır.
- **Tek işlem kuyruğu:** Aynı anda tek kopyalama/taşıma işlemi yürür (fikir birliği sağlamak için).
- **Klasör senkronizasyonu / kuru çalıştırma:** Henüz yok; karşılaştırma salt okunur rapor üretir.
- **Yerelleştirme:** Arayüz yalnızca Türkçe; İngilizce (`en.lproj`) çeviri bulunmuyor.
- **Erişilebilirlik:** VoiceOver ile kapsamlı bir ekran okuyucu turu yapılmadı.

## Lisans

Bu proje GMS için geliştirilmiştir. Referans olarak incelenen fman (MIT) kodundan hiçbir dosya
kopyalanmamıştır; yalnızca özellik kapsamı karşılaştırılmıştır.
