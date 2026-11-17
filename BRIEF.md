# Tetherline: brief

> Aktualizacja decyzji, 17.11.2026: użytkownik zlecił wariant bez certyfikatu Apple. Zastępuje on poniższy wymóg SMAppService.daemon i helpera wyłącznie w paczce: lokalny podpis ad-hoc, chroniona kopia silnika w `/Library/Application Support/Tetherline`, plist w `/Library/LaunchDaemons` i opcjonalny LaunchAgent interfejsu użytkownika. Instalowanie/usuwanie usługi wymaga systemowej autoryzacji administratora. Dalsza decyzja: jednorazowo instalowany kontroler na żądanie, aby start/stop/Quit nie pytały o hasło przy każdym użyciu. Dalej, 18.11.2026: usługa instalowana na stałe i przełączana przez launchd, jeden instalator-aktualizator, a automatyczna migracja starej muty usunięta za zgodą użytkownika (inna muta jest wykrywana jako konflikt). Aktualny opis: README.md. Pozostała treść zachowuje pierwotny brief.

## Cel

Aplikacja na macOS w pasku menu, która udostępnia Macowi internet z telefonu z Androidem po kablu USB (tethering USB, RNDIS). Silnikiem jest gotowy program **muta** (https://github.com/jost-s/macos-usb-tether-android, licencja MIT), wbudowany w aplikację bez zmian. Tetherline dodaje tylko ikonę w pasku menu, instalację i odinstalowanie.

Wymagania użytkownika:

1. **Jedna aplikacja** w `/Applications`, bez plików rozrzuconych po systemie. Odinstalowanie to przycisk w aplikacji i przeniesienie jej do kosza.
2. **Zmiany u autora muty trafiają do aplikacji po ręcznym „dociągnięciu”**, bez forka: podbija się wersję muty w jednym miejscu i przebudowuje.
3. **Ikona w pasku menu** ze stanem połączenia.

## Środowisko (sprawdzone)

- MacBook Pro M4 Pro, macOS 27.2, Xcode 27.2.
- Telefon Samsung Galaxy S23+, kabel USB‑C–USB‑C. W trybie tetheringu przedstawia się jako `04e8:6864`, RNDIS.
- muta 0.1.5 działa na tej maszynie (stan „connected”, interfejs `utun5`).
- muta jest teraz zainstalowana jako osobna usługa systemowa: `/usr/local/libexec/muta/muta`, `/Library/LaunchDaemons/com.github.jost-s.muta.plist`, `/etc/newsyslog.d/muta.conf`, log `/var/log/muta.log`. Przed pierwszym uruchomieniem usługi Tetherline trzeba ją usunąć (`sudo /usr/local/libexec/muta/muta uninstall`), bo dwie usługi walczyłyby o telefon. Aplikacja powinna to wykrywać i proponować.
- W `~/.zshrc` jest alias `muta=/usr/local/libexec/muta/muta`. Do usunięcia razem z migracją, za zgodą użytkownika.

## Interfejs muty (z `muta --help`)

```
muta run [-v]              tethering w pierwszym planie (root)
muta status                bieżące połączenie (bez roota)
muta probe                 opis podłączonego urządzenia RNDIS
muta install / uninstall   własna usługa muty (NIE używać w Tetherline)
muta --version
```

Przykładowy `muta status`:

```
state      connected
device     SAMSUNG SAMSUNG_Android (04e8:6864)
interface  utun5
address    10.221.188.173
gateway    10.221.188.209
dns        10.221.188.209
in         43597
out        40568
```

Usługa muty, którą trzeba odtworzyć w Tetherline: `ProgramArguments = [muta, run]`, `RunAtLoad`, `KeepAlive`, `ProcessType = Standard`. Autor celowo wyłącza ograniczanie procesów w tle, bo inaczej łącze zacina się, gdy Mac jest zajęty.

## Architektura

- **Aplikacja:** SwiftUI, `MenuBarExtra`, `LSUIElement = YES` (bez ikony w Docku), macOS 14+ (do ustalenia, wystarczy 27). Bez sandboxa.
- **Muta w paczce:** binarka w `Tetherline.app/Contents/MacOS/muta` (lub `Contents/Helpers/`), podpisana tym samym certyfikatem co aplikacja.
- **Usługa:** plist w `Contents/Library/LaunchDaemons/`, z `BundleProgram` wskazującym na mutę w paczce i argumentem `run`. Rejestracja i wyrejestrowanie przez `SMAppService.daemon(plistName:)` (nazwa z rozszerzeniem `.plist`). Usługa pojawi się w *Ustawieniach → Ogólne → Rzeczy otwierane podczas logowania* jako część Tetherline. Obsłuż stan `requiresApproval` z odesłaniem do Ustawień (`SMAppService.openSystemSettingsLoginItems()`).
- **Log:** zamiast `/var/log/muta.log` jedno miejsce przypisane do aplikacji, np. `/Library/Logs/Tetherline/muta.log`. Usuwane przy odinstalowaniu.
- **Stan:** aplikacja co kilka sekund uruchamia `muta status` (bez roota) i parsuje wynik. Nie wymyślaj własnego kanału komunikacji z usługą.
- **Pierwszeństwo Wi‑Fi:** macOS stawia Wi‑Fi wyżej niż połączenie z muty. Jeśli muta ma stan `connected`, ale domyślna trasa nie idzie przez jej `utun`, pokaż to (np. „Połączono, ale ruch idzie przez Wi‑Fi”).

## Aktualizacja muty (bez forka)

- Plik w repo, np. `Vendor/muta.version`: wersja (tag) i SHA‑256 archiwum `muta-universal-apple-darwin.tar.gz` z GitHub Releases.
- Skrypt budowania (faza Run Script w Xcode lub `make`) pobiera ten tag, weryfikuje sumę, rozpakowuje i kopiuje binarkę do paczki. Zła suma przerywa budowanie.
- Skrypt `scripts/bump-muta.sh <tag>` pobiera nowe wydanie, liczy sumę i aktualizuje plik wersji.
- Wersję muty pokazuj w menu („muta 0.1.5”).
- Licencja: dołącz `LICENSE` muty (MIT) do paczki i pokaż ją w „O aplikacji”.

## Podpisywanie

- Aplikacja i muta muszą mieć ten sam certyfikat wydany przez Apple. Podpis ad‑hoc daje według zgłoszeń problemy z `SMAppService`.
- Cel: na własny użytek działać na darmowym certyfikacie „Apple Development” (Xcode zalogowany Apple ID). **Sprawdź to w praktyce jako pierwszy krok** i zgłoś wynik. Developer ID i notaryzacja to wątek na przyszłość, nie teraz.
- Muta przy własnej instalacji odmawia uruchamiania z katalogu, który może podmienić nie‑root. Rozważ, czy uruchamianie z `/Applications` (zapisywalne dla adminów) przez `SMAppService` jest równoważnie bezpieczne. Wnioski opisz w README.

## Menu i ikona

- Ikona jednokolorowa (template), SF Symbol `cable.connector`:
  - połączono: wypełniona,
  - czeka na telefon: kontur,
  - usługa wyłączona: kontur z ukośną kreską.

  Stan pokazuj kształtem, nie kolorem.
- Menu: stan; urządzenie, adres i ruch (z `muta status`); „Włącz” / „Wyłącz” (rejestracja i wyrejestrowanie usługi); „Pokaż log”; „Uruchamiaj przy logowaniu” (sama aplikacja, `SMAppService.mainApp`); wersja muty; „Odinstaluj…”; „Zakończ”.
- „Odinstaluj…” wyrejestrowuje usługę, usuwa log i ustawienia aplikacji, a potem prosi o przeniesienie aplikacji do kosza.
- Teksty interfejsu po polsku.

## Poza zakresem

- Zmiany w kodzie muty i fork.
- Automatyczne aktualizacje (Sparkle itp.).
- Dystrybucja innym, Mac App Store, Intel.
- Tethering z iPhone’a.

## Kryteria odbioru

1. `Tetherline.app` w `/Applications` po włączeniu łączy Maca z internetem przez S23+ i przeżywa restart.
2. Poza paczką aplikacji istnieją tylko: rejestracja usługi w systemie, log w jednym katalogu Tetherline i ustawienia aplikacji.
3. Po „Odinstaluj…” i wyrzuceniu do kosza nic po aplikacji nie zostaje. Pokaż, jak to sprawdzono.
4. Zmiana wersji muty to jedno polecenie (`bump-muta.sh`) plus przebudowanie.
5. Ikona poprawnie zmienia trzy stany przy podłączaniu i odłączaniu telefonu oraz włączaniu i wyłączaniu tetheringu.
6. README: budowanie, podpisywanie, aktualizacja muty, migracja ze starej instalacji muty, wnioski o bezpieczeństwie.

## Najpierw sprawdź

- Czy `SMAppService.daemon` działa z darmowym certyfikatem „Apple Development” na macOS 27.
- Skąd `muta status` bierze stan bez roota (plik stanu? gniazdo?) i czy działa, gdy usługę uruchamia launchd z paczki.
- Czy wydania muty publikują sumy kontrolne. Jeśli nie, sumę liczy `bump-muta.sh`.

## Źródła

- muta: https://github.com/jost-s/macos-usb-tether-android
- Apple, SMAppService i helpery: https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos
- Apple Forums, podpis aplikacji i demona: https://developer.apple.com/forums/thread/757463
- Apple, MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
