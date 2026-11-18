# Tetherline: zasady działania

Szczegółowy opis działania, bezpieczeństwa i testów. Krótki opis dla użytkowników: [README](../README.md). Pierwotny brief: [BRIEF.md](BRIEF.md).

Natywna aplikacja macOS do tetheringu USB z Androida, oparta na niezmienionym silniku [muta](https://github.com/jost-s/macos-usb-tether-android). Apple Silicon i Intel (uniwersalna binarka), macOS 14+, SwiftUI i AppKit, bez sandboxa, kextów i rozszerzeń systemowych. Interfejs ma angielski język bazowy oraz automatyczną lokalizację polską.

## Budowanie

```sh
make test
make build
open build/Tetherline.app
```

Wymagane: Xcode z narzędziami wiersza poleceń i Python 3. **Konto Apple, certyfikat Apple Development i odnawianie certyfikatów nie są potrzebne.** Budowanie nakłada lokalny podpis ad-hoc, który pozwala uruchamiać kod ARM. Nie jest to podpis do dystrybucji ani notaryzacja.

`make build` pobiera przypiętą mutę i jej licencję, weryfikuje SHA-256 i buduje `build/Tetherline.app`. `make install` instaluje pierwszą kopię w `/Applications`; odmawia nadpisania istniejącej. Aplikacja przed operacjami sprawdza integralność własnej paczki i silnika, akceptując ad-hoc. Uszkodzona lub zmieniona binarka jest odrzucana.

Opcjonalny `SIGN_IDENTITY='ODCISK_CERTYFIKATU' make build` nadal działa, ale usługa nie wymaga certyfikatu Apple. Historyczne skrypty `probe-signing.sh` i `check-signing.sh` nie należą do zwykłego procesu budowania.

## Używanie

1. Uruchom `/Applications/Tetherline.app`.
2. Wybierz **Enable tethering**. Przy pierwszym włączeniu, i po aktualizacji aplikacji zmieniającej komponenty systemowe, zatwierdź systemową prośbę administratora.
3. Podłącz telefon i włącz tethering USB na Androidzie.

Instalacja kopiuje silnik i helper sterujący do chronionego katalogu oraz tworzy dwie konfiguracje `launchd` i log. Nie wykonuje `muta install`. Konfiguracja usługi zostaje na stałe; **Enable tethering** i **Turn off** przełączają ją systemowym przełącznikiem launchd (`enable`/`disable`). Ten przełącznik decyduje też o starcie po restarcie systemu: usługa wraca po restarcie wtedy i tylko wtedy, gdy była włączona. Zwykłe Enable, Turn off i Quit korzystają z helpera i nie pytają o hasło. Aplikacja nie przechowuje hasła i nie zmienia sudoers.

Hasło jest potrzebne tylko, gdy zainstalowane komponenty różnią się od paczki aplikacji: przy pierwszej instalacji, po aktualizacji muty lub helpera i przy odinstalowaniu. Aplikacja porównuje SHA-256 plików wykonywalnych i treść konfiguracji `launchd`; wtedy w stanie wyłączonym informuje, że włączenie poprosi o zgodę.

**Quit** w menu, **Quit Tetherline** w Settings, ⌘Q i Quit z Docka zatrzymują usługę przed zamknięciem aplikacji, bez hasła. Błąd zatrzymania pozostawia aplikację otwartą z komunikatem. Ustawienie uruchamiania interfejsu przy logowaniu pozostaje zapisane; zatrzymana usługa wymaga ponownego wybrania Enable tethering.

Interfejs pokazuje jeden stan: sprawdzanie, wyłączone, włączanie, wyłączanie, oczekiwanie na telefon, połączono, wymagana zgoda, inna muta lub błąd. Stan pochodzi z `launchd`, listy procesów i `muta status` zainstalowanego silnika, odczytywanych bez roota co sekundę przy otwartym panelu lub oknie i co pięć sekund w tle. Podczas włączania i wyłączania aplikacja nie odczytuje stanu, tylko pokazuje trwającą operację, a wynik publikuje po jej zakończeniu. Stany pośrednie (zadanie w trakcie wyładowania, silnik jeszcze bez gniazda stanu) nie są więc pokazywane jako błędy. Helper kończy start dopiero, gdy muta odpowiada, a stop, gdy proces silnika zniknął. Awaria działającej usługi usuwa dane połączenia, pokazuje czerwony błąd i zmienia ikonę. Spóźniony odczyt nie może nadpisać nowszego stanu. Oznaczenie USB potwierdza połączenie z telefonem, nie dostęp do internetu. Błąd operacji pozostaje widoczny po zamknięciu alertu, do kolejnej próby. **Liczniki `in` i `out` oznaczają pakiety, nie bajty ani prędkość.**

Inna muta w trybie usługi (`muta run`), np. instalacja upstream, blokuje włączenie i jest pokazywana jako konflikt. Krótkie wywołania `muta status` nie są konfliktem.

Komunikat o trasie porównuje interfejs muty z domyślną trasą IPv4 i interfejsami Wi-Fi z CoreWLAN. Nie jest gwarancją trasy każdego pakietu: VPN, szczegółowe trasy i IPv6 mogą zachowywać się inaczej. Aplikacja nie zmienia priorytetów interfejsów ani konfiguracji VPN.

## Menu i ustawienia

Przyciski menu, Settings i potwierdzeń korzystają ze wspólnego stylu (kapsuła, wysokość 34 pt). Neutralny wariant służy m.in. Cancel, Settings i View log; czerwony odinstalowaniu.

**Settings → App visibility** zawiera niezależne **Show in menu bar** i **Show in Dock**. Domyślnie widoczna jest tylko ikona paska menu. Wszystkie cztery kombinacje są zapamiętywane. Przy obu ikonach ukrytych ręczne otwarcie aplikacji z folderu Aplikacje pokazuje Settings. Kliknięcie Docka otwiera okno połączenia. Zmiany widoczności i zamykanie okien nie zatrzymują tetheringu.

**Launch at login** dotyczy tylko interfejsu. Używa osobnego LaunchAgenta użytkownika, bez certyfikatu i bez uprawnień administratora. Rejestracja nie tworzy drugiej instancji otwartej aplikacji. Uruchomienie przy logowaniu respektuje ukryte ikony i nie otwiera automatycznie okna ustawień. System może osobno ograniczyć działanie w tle; jeśli zgłosi brak zgody, aplikacja odsyła do Ustawień systemowych.

Ikona paska menu to SF Symbol `personalhotspot`, a przy wyłączonej usłudze `personalhotspot.slash`. Grubość semibold i pole rysowania 23 × 19 pt poprawiają czytelność. Grafitową ikonę Docka generuje `scripts/render-app-icon.swift` we wszystkich rozmiarach `.icns`.

Pasek menu i cykl życia obsługuje AppKit (`NSStatusItem`, `NSPopover`, `NSWindow`), a zawartość SwiftUI. Panel zna rozmiar treści przed otwarciem, jest zakotwiczony pod paskiem menu i zamyka się po ponownym kliknięciu, Escape lub kliknięciu poza nim. Język aplikacji można zmienić w systemowych ustawieniach Language & Region → Applications.

## Pliki i bezpieczeństwo usługi

Paczka zawiera interfejs, mutę, helper TetherlineControl, licencję, wersję, lokalizacje, ikonę oraz referencyjny plist. Podczas instalowania rzeczywisty plist powstaje z konfiguracji skompilowanej w aplikacji. Weryfikuje go również test zgodności z plikiem referencyjnym.

Poza paczką występują:

- `/Library/Application Support/Tetherline/muta` — chroniona kopia silnika, root:wheel, 0755; katalog 0755.
- `/Library/Application Support/Tetherline/TetherlineControl` — ograniczony helper, root:wheel, 0755.
- `/Library/Application Support/Tetherline/control.sock` — socket sterujący tworzony przez launchd; dostęp do poleceń wymaga właściwego UID klienta.
- `/Library/LaunchDaemons/pl.tetherline.control.plist` — aktywacja helpera na żądanie i UID konta instalującego.
- `/Library/Logs/Tetherline/control.log` — log helpera.
- `/Library/LaunchDaemons/pl.tetherline.muta.plist` — stała konfiguracja usługi, root:wheel, 0644. Włączenie i start po restarcie wynikają z przełącznika `launchctl enable/disable`.
- `/Library/Logs/Tetherline/muta.log` — log, root:wheel, 0644; katalog 0755.
- `~/Library/LaunchAgents/pl.tetherline.app.plist` — tylko gdy włączono uruchamianie interfejsu przy logowaniu.
- Preferencje `pl.tetherline.app`, cache i saved state tworzone przez macOS.
- `/var/run/muta.sock` — stała ścieżka zaszyta w upstream. Socket stanu jest dostępny także bez roota; niezmodyfikowana muta wymaga go do `muta status`.

To świadoma zmiana względem pierwotnego briefu: użytkownik wybrał działanie bez certyfikatu Apple zamiast utrzymywania helpera wyłącznie w paczce przez `SMAppService.daemon`.

Usługa używa bezwzględnej ścieżki chronionej kopii, `muta run`, `RunAtLoad`, `KeepAlive` i `ProcessType = Standard`. Nie uruchamia kodu roota bezpośrednio z paczki, którą użytkownik może zastąpić.

Instalator jest jeden dla pierwszej instalacji i aktualizacji. Doprowadza system do stanu paczki i zmienia tylko to, co się różni; ponowne uruchomienie niczego nie zmienia. Odrzuca dowiązania symboliczne, pliki z wieloma hardlinkami, nieprawidłowych właścicieli, katalogi i pliki zapisywalne przez innych oraz nieoczekiwane ACL. Kopiuje pliki do tymczasowego katalogu roota, sprawdza ich SHA-256 względem wartości odczytanych przed autoryzacją i weryfikuje podpis ad-hoc. Zdejmuje z kopii kwarantannę: kopie pobranej aplikacji ją dziedziczą, a system zabija przy starcie niezatwierdzony plik wykonywalny z podpisem ad-hoc. Dopiero wtedy podmienia docelowe pliki. Wymiana helpera nie przerywa działającego silnika. Wymiana silnika lub jego konfiguracji restartuje go tylko, jeśli działał. Wyłączony silnik zostaje wyłączony również po restarcie systemu. Blokada operacji chroni przed równoczesną instalacją i usuwaniem.

Helper sterujący ma tylko dwa polecenia: `start` i `stop`. Nie przyjmuje ścieżek, argumentów procesu, kodu ani poleceń powłoki; start i stop wykonuje bez powłoki. Ścieżki i etykiety są skompilowane w helperze, a przed startem sprawdza on właściciela, uprawnienia i treść zainstalowanej konfiguracji. `getpeereid` weryfikuje UID klienta: dostęp ma tylko konto wskazane przy instalacji oraz root. Klient wymaga serwera z UID 0. Błędy helper zgłasza stałymi kodami, które aplikacja tłumaczy. To uprawnienie dla konta, a nie konkretnej aplikacji: inne programy tego samego użytkownika mogą włączać i wyłączać wyłącznie tę usługę. Nie mogą wykonać dowolnego polecenia jako root. Helper jest kompilowany tylko z potrzebnych mu plików, więc zmiany samego interfejsu nie zmieniają jego sumy i nie wymagają hasła.

Helper używa aktywacji socketem [launch_activate_socket](https://developer.apple.com/documentation/xpc/launch_activate_socket) i [konfiguracji launchd Apple](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5). Nie ma KeepAlive ani RunAtLoad; po sekundzie bezczynności proces kończy działanie, a uruchamia się tylko przy starcie i zatrzymaniu, nie przy odczycie stanu. Zapisuje krótki dziennik poleceń w `control.log`.

Podpis ad-hoc sprawdza integralność, ale nie tożsamość wydawcy. Systemowa zgoda administratora oznacza zaufanie do uruchomionej lokalnej aplikacji. Nie jest to model dystrybucji podpisanej i notaryzowanej aplikacji dla innych użytkowników.

Pliki `.stage.*` oraz `.operation-lock` są tymczasowe i usuwane po zakończeniu operacji. Po wymuszonym zabiciu procesu instalatora mogą wymagać ręcznego usunięcia z chronionego katalogu, po upewnieniu się, że żadna operacja nie trwa. Nie ma automatycznej rotacji logu: muta v0.1.5 obsługuje ponowne otwarcie logu wyłącznie pod swoją oryginalną ścieżką. Po wyłączeniu usługi można opróżnić log.

## Aktualizacja

```sh
./scripts/bump-muta.sh v0.1.5  # zastąp tagiem wybranego wydania
make build
```

`Vendor/muta.version` jest jedynym źródłem wersji i zawiera tag oraz sumy SHA-256 archiwum i licencji. Skrypt sprawdza publikowaną sumę, jeśli wydanie ją udostępnia; tylko HTTP 404 pozwala użyć sumy obliczonej lokalnie. Błąd sieci lub rozbieżność zatrzymuje aktualizację. Cache jest sprawdzany przy każdym budowaniu, a błędne pobranie go nie zastępuje. Z archiwum pobierana jest jedna zwykła binarka bez rozpakowywania dowiązań. Kod muty nie jest modyfikowany.

Zastąpienie `.app` niczego nie podmienia w systemie. Jeśli nowa paczka zawiera inny silnik lub helper, aplikacja w stanie wyłączonym zapowiada prośbę o zgodę, a **Enable tethering** aktualizuje komponenty i włącza usługę. Działający tethering nie jest przerywany do czasu Turn off i ponownego Enable. Nie nadpisuj chronionych plików ręcznie podczas pracy.

## Odinstalowanie

**Uninstall…** wyłącza autostart interfejsu, zatrzymuje helper i usługę, czeka na zakończenie procesów i usuwa oba plisty, chronione binarki, socket sterujący, logi oraz puste katalogi. Nie usuwa nieznanych plików w katalogach; wtedy zgłasza błąd. Socket stanu muty usuwa tylko, gdy nie działa żadna muta. Czyści własne preferencje, cache i saved state, a następnie wskazuje aplikację w Finderze i kończy działanie. Przenieś `.app` do Kosza. Wpis przełącznika `launchd` dla etykiety usługi pozostaje w systemowej bazie launchd; nie jest plikiem aplikacji i nie ma wpływu bez jej konfiguracji.

Wcześniejsza instalacja muty spoza Tetherline nie jest już migrowana automatycznie. Jeśli działa, aplikacja pokazuje konflikt; usuń ją poleceniem `sudo muta uninstall`.

```sh
./scripts/verify-uninstalled.sh
launchctl print system/pl.tetherline.muta
```

Audyt niczego nie usuwa. Sprawdza dokładne ścieżki, proces i zadania launchd; sygnalizuje socket mogący należeć do innej muty. Nie usuwa systemowej historii logów ani bazy Background Task Management. Repozytorium i artefakty budowania pozostają osobno.

## Sprawdzenie

- `make test`: parser, procesy, odczyt stanu `launchd`, fazy interfejsu, porównanie instalacji, skrypty instalatora, protokół helpera, preferencje, pakowanie oraz model aplikacji (m.in. brak błędu podczas wyłączania, częstotliwość odczytów, zamykanie).
- `bash scripts/test-control.sh`: wymaga systemowej zgody administratora. Izolowana kopia usługi z atrapą silnika, która tylko sprawdza UID 0 i czeka: odrzucanie złej sumy i dowiązań, instalacja, idempotencja, aktualizacja bez restartu i z restartem, start/stop jako zwykły użytkownik, przełącznik startu po restarcie, konflikt z inną mutą, migracja poprzedniego układu, aktywacja na żądanie, odrzucanie innego konta i poleceń, pełne odinstalowanie. Nie uruchamia muty ani nie dotyka USB. `--prepare-only` przygotowuje skrypt do przejrzenia; `--install-production` po zaliczeniu testów instaluje lub aktualizuje komponenty z `build/Tetherline.app` w tej samej autoryzacji.
- `bash scripts/test-quit.sh`: rzeczywisty cykl zamykania AppKit z kontrolowanym, opóźnionym zatrzymaniem usługi.
- `bash scripts/test-login-item.sh`: instaluje i usuwa osobny LaunchAgent uruchamiający `/usr/bin/true`; nie zmienia autostartu właściwej aplikacji.
- `bash scripts/test-visibility.sh` oraz `bash scripts/test-popover.sh`: testy GUI w izolowanych domenach preferencji; wymagają sesji graficznej.
- `./scripts/render-previews.sh`: rzeczywiste podglądy SwiftUI wszystkich stanów EN/PL w jasnym i ciemnym motywie w `.build/previews`.
- `/Applications/Tetherline.app/Contents/MacOS/Tetherline --diagnose`: odczyt stanu instalacji i usługi bez zmian w systemie.

Wyniki, ograniczenia i historyczny test certyfikatu opisano w [VALIDATION.md](VALIDATION.md). Test helpera nie zastępuje testu połączenia z telefonem ani restartu całego Maca.
