# GMS Commander — Geliştirme Notları

## 1. Ortam

| Bileşen | Bu makinede doğrulanan durum |
|---|---|
| macOS | 26.6.2 (Apple Silicon) |
| Swift derleyicisi | `swiftc` 6.0 (Apple Swift 6.0), hedef `arm64-apple-macos14.0` |
| SDK | Command Line Tools SDK (`xcrun --show-sdk-path`) |
| Xcode.app | **Kurulu değil** → `xcodebuild` ve XCTest koşturulamıyor |
| Python | 3 (proje üretici betik için) |
| Araçlar | `hdiutil`, `codesign`, `iconutil`, `sips`, `plutil`, `PlistBuddy` |

Uygulama Swift **dil sürümü 5** ile derlenir (`-swift-version 5`); Swift 6 dil modu
kapatılmıştır, ancak eşzamanlılık uyarıları ciddiye alınır (bu projede derleme uyarısız geçer).

## 2. Komutlar

```bash
# Hızlı söz dizimi/tip denetimi (en sık kullanılan döngü)
swiftc -target arm64-apple-macos14.0 -sdk "$(xcrun --show-sdk-path)" \
       -typecheck -parse-as-library $(find GMS_Commander -name '*.swift')

# Uygulamayı derle ve paketle
./Scripts/build.sh
open "build/GMS Commander.app"

# Bağımsız test koşucusu (175 doğrulama, Xcode gerekmez)
./Scripts/test.sh

# Xcode kurulu bir makinede XCTest paketi
./Scripts/test.sh --xcode

# DMG üret + doğrula
./Scripts/create_dmg.sh

# Xcode projesini yeniden üret
python3 Scripts/generate_xcodeproj.py

# Temizlik
./Scripts/clean.sh
```

## 3. Geliştirme döngüsü (VS Code)

1. `GMS_Commander/**/*.swift` dosyalarını düzenle.
2. Yukarıdaki `swiftc -typecheck` komutunu çalıştır (yaklaşık 5–10 sn).
3. `./Scripts/test.sh` ile davranışı doğrula.
4. `./Scripts/build.sh` + `open "build/GMS Commander.app"` ile arayüzü gör.
5. Yeni dosya eklediysen `python3 Scripts/generate_xcodeproj.py` ile projeyi tazele.

VS Code için önerilen uzantılar: **Swift** (swiftlang.swift-vscode), **Even Better TOML** (gerekmez),
**Markdown All in One**. `tasks.json` örneği:

```json
{
  "version": "2.0.0",
  "tasks": [
    { "label": "tip denetimi", "type": "shell",
      "command": "swiftc -target arm64-apple-macos14.0 -sdk \"$(xcrun --show-sdk-path)\" -typecheck -parse-as-library $(find GMS_Commander -name '*.swift')",
      "problemMatcher": [] },
    { "label": "derle", "type": "shell", "command": "./Scripts/build.sh", "problemMatcher": [] },
    { "label": "test", "type": "shell", "command": "./Scripts/test.sh", "problemMatcher": [] }
  ]
}
```

## 4. Yeni dosya ekleme kuralları

- Uygulama kaynakları **yalnızca** `GMS_Commander/` altında olmalı; `Scripts/generate_xcodeproj.py`
  bu dizini tarar ve alt grupları otomatik kurar.
- Testler `Tests/GMSCommanderTests/` altında; her dosya `@testable import GMS_Commander` ile başlar.
- `Resources/tr.lproj/Localizable.strings` yeni anahtarlar `"anahtar" = "Türkçe metin";` biçiminde eklenir.
  `L.t` çağrılarında anahtar eksikse ekranda anahtarın kendisi görünür — bu bir hatadır, anahtarı ekleyin.
- Proje üretildikten sonra `plutil -lint GMS_Commander.xcodeproj/project.pbxproj` ile doğrula.

## 5. Tuzaklar ve çözümleri

**A. `/var` ile `/private/var`**
`FileManager.default.temporaryDirectory` ve dizin numaralandırması farklı ön ek döndürebilir.
`URL.resolvingSymlinksInPath()` bunu çözmez. Çözüm: POSIX `realpath(3)` (testlerde `TestSupport.realPath`)
veya `standardizedFileURL.path` karşılaştırması (`DirectorySnapshot.item(at:)` böyle yapar).

**B. Türkçe katlama**
`Locale(identifier: "tr_TR")` ile `folding` yapıldığında `I → ı`, `İ → ı` olur ve "isik" araması
"ışık" ile eşleşmez. `FileSearchService.normalize` bu yüzden `en_US_POSIX` kullanır ve `ı → i` dönüşümü ekler.

**C. Kök klasör testi**
`URL.deletingLastPathComponent()` `/` için `/..` döndürür; `parent.path == path` yanlış sonuç verir.
`FileManagerService.isRoot` standartlaştırılmış yol + `/` özel durumu ile çalışır.

**D. `NSEvent` ve Swift 6 eşzamanlılığı**
`NSEvent` `Sendable` değildir. Yerel olay izleyicisinde olay nesnesini eşzamanlılık sınırının içine
taşımayın; `keyCode` ve `modifierFlags` gibi değerleri dışarıda çıkarıp `MainActor.assumeIsolated`
içinde kullanın (`KeyboardShortcutManager.swift`).

**E. `@Sendable` ilerleme kapanışları**
`copySync`/`moveSync` ilerleme kapanışları `@Sendable`. Sayaç tutmak için `var` yakalamak yerine
`final class Sayaç: @unchecked Sendable` kullanın (hem uygulamada hem testlerde böyle yapıldı).

**F. SwiftUI kısayol tuşları**
`KeyEquivalent` için hazır `F5`/`F6` yoktur ve menü tuş eşdeğerleri odaklanmış `NSTableView`
ile çakışabilir. Bu yüzden `F3`–`F10` menüye değil `KeyboardShortcutManager` kataloğuna ve
yerel olay izleyicisine bırakıldı; keyCode tablosu: F3=99, F4=118, F5=96, F6=97, F7=98,
F8=100, F9=101, F10=109. İşlev tuşları metin alanı odaklıyken de çalışır.
`SettingsLink` yalnızca `Scene` bağlamında çalışır; burada `Settings` sahnesi + `⌘,` kullanıldı.

**G. SwiftUI `List(selection:)` + çift tıklama**
`List(selection:)` ile `.simultaneousGesture(TapGesture(count: 2))` birlikte kullanıldığında çift
tıklama tanıyıcısı tek tıklamayı yutuyor ve seçim başka satıra taşınmıyordu. Dosya listesi bu yüzden
AppKit `NSTableView` (`Views/FileTableView.swift`) ile yazıldı; seçim iki yönlü `revision` +
`isApplyingSelection` bayrağıyla eşitlenir.

**H. Menüye `Return`/`Space`/`⌫` eklemeyin**
Bunlar metin alanlarında yazılan karakterlerle çakışır (menü tuş eşdeğerleri alan editöründen önce
çalışır). Bu yüzden yalın tuşlar yerel olay izleyicisiyle yönlendirilir.

## 6. Sürüm çıkarma

1. `GMS_Commander/Resources/Info.plist` içindeki `CFBundleShortVersionString` değerini artır.
2. `Scripts/create_dmg.sh` içindeki sürüm değişkenini güncelle.
3. `./Scripts/clean.sh && ./Scripts/build.sh && ./Scripts/test.sh && ./Scripts/create_dmg.sh`.
4. Dağıtım imzası gerekiyorsa:
   `codesign --deep --force --options runtime --sign "Developer ID Application: …" "build/GMS Commander.app"`
   ardından `xcrun notarytool submit … && xcrun stapler staple`.
5. DMG'yi yayınla; sürüm notlarını `README.md` ve `Documentation/TEST_RAPORU.md` ile güncelle.

## 7. Kod stili

- Türkçe doc-comment (`///`) ve satır içi yorumlar; tanımlayıcılar İngilizce (Swift API gelenekleri).
- Görünüm dosyaları mümkün olduğunca "aptal" tutulur; hesaplama ViewModel/servislerde yapılır.
- Servisler `Sendable`/`async` API sunar, arayüz bilmez.
- Yeni özellik eklerken: model → servis → view model → görünüm sırasıyla ilerleyin ve her adımda
  `swiftc -typecheck` çalıştırın.
- AppKit tablo hücreleri `Theme`/`Palette` sabitlerini kullanır; görünümlerde sabit renk yazmayın.
- `FileTableView.Coordinator` `@MainActor` olmalıdır; aksi hâlde `panel.revision` gibi ana iş parçacığı
  özelliklerine erişim derlenmez.
