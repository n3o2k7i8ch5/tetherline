# Wyniki sprawdzenia — 17 listopada 2026

Maszyna: Apple Silicon, macOS 27.2 (26B123), Xcode 27.2, Swift 6.4.2. Testowane wydanie: muta v0.1.5. Wyniki poniżej rozdzielają działającą poprzednią instalację od nowej usługi Tetherline.

Historyczna decyzja podczas pracy nad interfejsem: podpisywanie i testy usługi systemowej były odłożone. Aktualnie użytkownik wybrał klasyczny launchd z podpisem ad-hoc; nowe wyniki są na końcu dokumentu. `make build` domyślnie tworzy lokalną paczkę ad-hoc bez wymagania certyfikatu Apple. Poniższe wyniki podpisywania są zapisem wcześniejszych testów, nie warunkiem dalszej pracy nad interfejsem.

## Podpis

Początkowy Apple Development wygasł 29.10.2026. `security find-identity -v -p codesigning` pokazywało wyłącznie Apple Distribution. Próba użycia odcisku wygasłego certyfikatu przez `codesign` zwróciła `no identity found`.

Po ponownym zalogowaniu użytkownika do Xcode, automatyczne podpisywanie (`xcodebuild -allowProvisioningUpdates`) utworzyło nowy Apple Development. Minimalna aplikacja Xcode zbudowała się z wynikiem `BUILD SUCCEEDED`. Następnie właściwe `scripts/build.sh` podpisało aplikację i dołączoną mutę tym samym nowym certyfikatem. `codesign --verify --deep --strict` zakończyło się powodzeniem.

To certyfikat zespołu J8VJ6UR5V8, który posiada również Apple Distribution. Wynik **nie dowodzi działania z bezpłatnym Personal Team**.

Osobna `TetherlineSigningProbe.app` została umieszczona w `/Applications`. Rejestracja `SMAppService.daemon` zwróciła początkowo `SMAppServiceErrorDomain Code=1 Operation not permitted`, ale stan po wywołaniu wynosił **2 (`requiresApproval`)**. Log systemu potwierdza wpis testowej usługi z `disallowed`. Oznacza to zarejestrowaną usługę oczekującą na zgodę, a nie dowiedzione uruchomienie roota. Aplikacja obsługuje teraz ten przypadek: odczytuje stan po błędzie i kieruje do Ustawień.

Po zgodzie użytkownika stan zmienił się na **1 (`enabled`)**. `launchctl print system/pl.tetherline.signing-probe` pokazało `state = running`, `runs = 1`, PID **22374**, `last exit code = (never exited)`. `ps -p 22374 -o pid=,uid=,comm=` zwróciło `22374 0 helper`: **UID 0 potwierdzone**. To praktyczne potwierdzenie uruchomienia LaunchDaemona podpisanego Apple Development z paczki w `/Applications` na macOS 27.2.

`probe-signing.sh cleanup` zakończyło się sukcesem, status wrócił do **0 (`notRegistered`)**, testowa paczka zniknęła, a `launchctl print` zgłosiło brak usługi. Poprzednie połączenie z Samsungiem pozostało `connected` na `utun5`.

## Kompilacja i testy automatyczne

- `make test`: **9 testów Swift + 4 testy pakowania Python, 0 błędów**.
- Kompilacja Swift 6 w trybie release dla `arm64-apple-macosx14.0`: powodzenie.
- `plutil -lint`: oba pliki plist poprawne.
- `bash -n`: skrypty powłoki poprawne składniowo.
- Próba podmienionego pobrania: zła suma SHA-256 powoduje błąd i nie zastępuje dotychczasowego cache.
- Przekroczony czas `muta status` jest obsługiwany przez przetestowany limit procesu. Wyjście większe od bufora nie blokuje procesu.
- Aplikacja została uruchomiona jako aplikacja menu; proces pozostał aktywny. Nie przeprowadzono automatycznego testu klikania całego interfejsu.
- Podpisana aplikacja została zainstalowana i uruchomiona w `/Applications/Tetherline.app`. Przy pierwszej instalacji macOS zwrócił `notFound` dla jeszcze niezarejestrowanych usług mimo obecności poprawnego plist; menu traktuje ten przypadek jako usługę wyłączoną.

## Muta z paczki

`build/Tetherline.app/Contents/MacOS/muta --version` zwraca `muta 0.1.5`. `Tetherline --diagnose` uruchamia dołączone `muta status` jako zwykły użytkownik i uzyskuje wyjście:

```text
state      connected
device     SAMSUNG SAMSUNG_Android (04e8:6864)
interface  utun5
address    10.221.188.173
gateway    10.221.188.209
dns        10.221.188.209
```

W tym teście socket obsługuje **poprzednia instalacja muty**, a nie demon Tetherline. Wynik dowodzi poprawności pakowania klienta i odczytu bez roota, nie nowej usługi USB.

`route -n get default` pokazało `utun5`. Parser i komunikaty dla Wi-Fi, innego `utun` oraz braku trasy sprawdzono testami jednostkowymi. Rzeczywistego przełączenia na Wi-Fi nie wymuszano.

Przejrzano kod upstream v0.1.5: `src/status.rs` używa `/var/run/muta.sock` z prawami 0666; `src/service.rs` tworzy PID dla obsługi rotacji wyłącznie, gdy stderr wskazuje oryginalny `/var/log/muta.log`. Stąd jawny wyjątek od wymagań dotyczących lokalizacji plików i brak własnej rotacji logu. Źródła: [status.rs](https://github.com/jost-s/macos-usb-tether-android/blob/v0.1.5/src/status.rs), [service.rs](https://github.com/jost-s/macos-usb-tether-android/blob/v0.1.5/src/service.rs).

## Stan migracji i odinstalowania

Poprzedniej działającej usługi nie odinstalowano w trakcie tworzenia aplikacji. Alias użytkownika pozostawiono bez zmian. Migracja wymaga wybrania odpowiedniej akcji w aplikacji, ponieważ przerwie obecne połączenie; usunięcie aliasu ma osobną zgodę.

Uruchomiono `verify-uninstalled.sh` **przed pierwszą instalacją właściwej aplikacji**: nie było plików, procesu ani załadowanego zadania Tetherline. Skrypt poprawnie ostrzegł o sockecie działającej poprzedniej muty. To pomiar bazowy, **nie test pełnego odinstalowania**.

## Pozostały odbiór ręczny

Po uwagach użytkownika zmieniono bazowy język na angielski, dodano 67 tłumaczeń polskich i przeprojektowano menu: czerwony panel konfliktu, przycisk migracji, osobna sekcja połączenia, wyraźne przyciski oraz przełącznik autostartu. `AppleLanguages` na tym Macu to `en-US, pl-PL`, więc domyślnie wyświetlany jest angielski. Wygenerowano 16 natywnych podglądów SwiftUI (4 stany × 2 języki × 2 motywy), sprawdzono wizualnie warianty EN/PL i ponownie wykonano wszystkie 13 testów bez błędów. Podglądy wykorzystują dane testowe i nie potwierdzają fizycznego połączenia nową usługą.

- [x] Zatwierdzić testowy demon, potwierdzić `state = running` i UID 0 (PID 22374), wyrejestrować usługę i usunąć paczkę.
- [ ] Jeśli wymagany jest dowód dla darmowego konta: powtórzyć test z certyfikatem Personal Team.
- [ ] Wybrać migrację starej muty, opcjonalnie usunąć alias.
- [ ] Włączyć Tetherline, zatwierdzić usługę, potwierdzić połączenie z S23+ i ruch przez nową instancję.
- [ ] Odłączyć/podłączyć kabel; wyłączyć/włączyć tethering; sprawdzić ikonę i dane w menu.
- [ ] Włączyć Wi-Fi i sprawdzić komunikat o zmianie domyślnej trasy; uwzględnić VPN.
- [ ] Włączyć uruchamianie przy logowaniu; zrestartować Maca i potwierdzić usługę oraz menu.
- [ ] Wybrać Odinstaluj, zamknąć aplikację, usunąć ją do Kosza, uruchomić audyt i sprawdzić Ustawienia.

Bez tych kroków kryteria odbioru dotyczące restartu, pełnego połączenia nową usługą i całkowitego odinstalowania pozostają niepotwierdzone.

## Widoczność aplikacji i nowa ikona — 2026-11-17

- Zastosowano SF Symbol `personalhotspot` w pasku menu oraz ikonę `.icns` z grafitowym tłem w Docku.
- Dodano niezależne, zapisywane przełączniki paska menu i Docka w Settings, z lokalizacją EN/PL.
- `make test`: 12 testów Swift i 4 testy pakowania bez błędów. Trzy nowe testy obejmują domyślne preferencje, zapis wszystkich czterech kombinacji i wybór okna przy ponownym uruchomieniu.
- `bash scripts/test-visibility.sh`: osobny proces GUI i osobna domena preferencji; pięć przełączeń obejmujących cztery kombinacje oraz powrót do ustawienia domyślnego. Sprawdzono rzeczywistą politykę Docka, obecność NSStatusItem, zapis preferencji, zamykanie i ponowne otwieranie okien. Wszystkie przeszły.
- Test ujawnił błędną interpretację wyniku `setActivationPolicy` przy ustawieniu już aktywnej polityki. Poprawiono ją i ponowiono test z wynikiem pozytywnym.
- Pierwotna implementacja ze scenami SwiftUI wywoływała rekurencję AppGraph i awarię podczas ponownego otwierania. Zastąpiono zarządzanie cyklem życia, oknami i paskiem menu przez AppKit, pozostawiając zawartość SwiftUI. Minimalna wersja pozostała macOS 14.
- Wygenerowano podglądy ustawień i migracji EN/PL w jasnym i ciemnym motywie; sprawdzono układ przełączników i czytelność.
- Zmiany i testy widoczności nie rejestrują ani nie zatrzymują demona; test nowej usługi USB nadal pozostaje osobnym etapem.

## Poprawka panelu paska menu i grubości ikony — 2026-11-17

- Odtworzono błąd geometrii: NSPopover miał `contentSize = 320 × 320`, podczas gdy jego widok SwiftUI miał `380 × 362`. Okno kończyło się na Y=1180 przy wysokości ekranu 1169, zasłaniając pasek menu. Panel nie miał też fokusu klawiatury.
- Rozmiar widoku jest teraz ustalany przed przypisaniem kontrolera i przed otwarciem panelu; aktualizowany także przy zmianach danych. Kotwicą jest dolna krawędź odwróconego NSStatusBarButton. Aplikacja aktywuje panel i nadaje mu fokus.
- Wyłączono animację popovera. Zmiana rozmiaru treści nie wywołuje ponownie `show`, co zapobiega ponownemu otwieraniu panelu zamykanego w tym samym czasie.
- Dodano monitory myszy działające tylko podczas otwarcia panelu i lokalną obsługę Escape. Przejście do Settings zamyka panel.
- `bash scripts/test-popover.sh`: w trybie bez Docka oraz z Dockiem potwierdzono poprawną geometrię i fokus, utrzymanie treści poniżej paska po zwiększeniu wysokości, zamknięcie drugim kliknięciem, Escape i kliknięciem w inne okno oraz otwarcie Settings po zamknięciu panelu.
- Zachowano aktualny SF Symbol. Zmieniono grubość z light/regular na semibold i powiększono obszar rysowania z 20 × 18 do 23 × 19 pt.
- Systemowy zrzut całego ekranu był niedostępny (`could not create image from display`); test panelu opiera się na rzeczywistych współrzędnych okien, stanie fokusu i zdarzeniach AppKit.

## Spójne przyciski — 2026-11-17

Zastąpiono osobne style przycisków głównych i dolnych jednym `ActionButtonStyle`: kapsuła, wysokość 34 pt, tekst 13 pt medium, wspólne odstępy i stany hover/pressed/disabled. Wariant neutralny służy m.in. Cancel, Settings i View log; standardowy akcjom głównym; czerwony migracji i odinstalowaniu. Ten sam styl obejmuje przyciski Settings, link do źródeł i oba potwierdzenia. Natywne komunikaty błędów i systemowa autoryzacja pozostają kontrolowane przez macOS.

Wyrenderowano potwierdzenia migracji i odinstalowania, menu oraz Settings w EN/PL, jasnym i ciemnym motywie. Migrację wydzielono do osobnego widoku, by jej podgląd odczytywał rzeczywisty motyw z otoczenia. Test zachowania panelu paska menu przeszedł dla obu ustawień Docka.

## Wariant bez certyfikatu Apple — 2026-11-17

- Na wyraźne zlecenie użytkownika zastąpiono SMAppService.daemon klasyczną instalacją launchd. Aplikacja i silnik zachowują automatyczny podpis ad-hoc. Walidacja integralności akceptuje go bez Apple-issued anchor i bez sprawdzania tożsamości certyfikatu.
- Chroniona kopia silnika: `/Library/Application Support/Tetherline/muta`. Konfiguracja: `/Library/LaunchDaemons/pl.tetherline.muta.plist`. Pliki roota powstają dopiero po systemowej autoryzacji. Wyłączenie usuwa konfigurację, odinstalowanie także silnik i log. Instalator weryfikuje SHA-256 kopii po autoryzacji i odrzuca niebezpieczne ścieżki.
- Autostart interfejsu używa `~/Library/LaunchAgents/pl.tetherline.app.plist`. `bash scripts/test-login-item.sh` potwierdził instalację i załadowanie izolowanego agenta bez certyfikatu oraz jego pełne i powtarzalne usunięcie.
- `make test`: 16 testów Swift i 4 testy pakowania bez błędów. Nowe testy obejmują cytowanie ścieżek z apostrofami, poleceniami i nową linią, walidację sumy, składnię skryptów oraz zgodność rzeczywistej konfiguracji z plikiem referencyjnym.
- `make build` i kontrola podpisów ad-hoc: powodzenie. Diagnostyka nowej paczki zgłasza `Code integrity: valid (ad-hoc supported; no Apple certificate required)`.
- `bash scripts/test-local-service.sh`: po systemowej autoryzacji wszystkie etapy przeszły. Odrzucono złą sumę i dowiązanie w docelowej ścieżce; helper podpisany ad-hoc działał jako UID 0 (PID 38435), z prawami 0755 i plistem 0644. Odrzucono podmianę działającej usługi, potwierdzono wyłączenie, ponowne włączenie oraz pełne usunięcie. Po teście nie ma zadania `pl.tetherline.local-probe`, katalogu helpera, logu ani plist.
- Ponowny test panelu menu przeszedł z Dockiem włączonym i wyłączonym. Nie wykonano jeszcze migracji prawdziwej muty, testu USB nową usługą ani restartu Maca.

- Nowy build zainstalowano w `/Applications/Tetherline.app`. Kontrola integralności paczki oraz dołączonej muty przechodzi z ad-hoc. Usunięto z paczki nieaktualny katalog plistów SMAppService; kopia poprzedniej wersji jest w `.build/previous-app`.
- Wywołanie zainstalowanej aplikacji z `--login-item` przy działającym interfejsie zakończyło się bez utworzenia drugiego procesu. LaunchAgent używa krótkiego launchera przez Launch Services, aby jego usunięcie nie zabijało interfejsu usuwającego autostart.
- Poprzednia muta nadal działa jako PID 85056. Ostatni odczyt stanu: `waiting`; nie migrowano jej ani nie uruchomiono nowej usługi na telefonie.

## Oczekiwanie na zakończenie migracji — 2026-11-17

Zgłoszony błąd „The previous service is still loaded” wystąpił po usunięciu plików przez upstream. W odczycie wykonanym po zgłoszeniu nie było już zadania `com.github.jost-s.muta`, procesu, starej binarki, konfiguracji ani logów/socketu. Poprzednia implementacja sprawdzała launchd natychmiast po powrocie odinstalatora i zgłaszała błąd, zanim skończyło się asynchroniczne wyrejestrowanie.

Migracja teraz czeka, w razie potrzeby wykonuje bootout po etykiecie (bez potrzeby istnienia plist), potwierdza zakończenie procesu i obsługuje ponowienie po częściowym usunięciu plików. Nie zatrzymuje obcego programu używającego tej samej etykiety i nie usuwa współdzielonego socketu, gdy działa inna muta.

Dodano 8 testów regresyjnych wykonujących skrypt z izolowanymi zamiennikami launchctl/ps: opóźnione wyrejestrowanie, pozostałe zadanie bez plist, wyścig przy bootout, ponowienie po zakończonym usuwaniu, odmowę bootout, obcą etykietę, pozostały proces oraz składnię pełnego skryptu. Pełny zestaw: 24 testy Swift i 4 testy pakowania, wszystkie przeszły.

## Stan UI po awarii usługi — 17.11.2026

Po zgłoszeniu błędnego stanu UI nie było zadania `pl.tetherline.muta`, procesu muty, chronionego helpera, plist ani logu. `muta status` zwracało exit 1 / brak socketu. Nie udało się odtworzyć pierwotnej awarii silnika; nie ma podstaw do przypisania jej konkretnej przyczyny. Interfejs Tetherline pozostawał uruchomiony.

Usunięto przerwę w monitorowaniu podczas operacji. Odczyt weryfikuje własny program i PID launchd przed i po odpowiedzi silnika, a stan i dane połączenia są publikowane razem; starszy odczyt nie nadpisuje nowszego. Ikona nie uznaje samej rejestracji za działający proces. Błędy operacji pozostają w czerwonym komunikacie po zamknięciu alertu. Etykieta USB nie sugeruje potwierdzonego dostępu do internetu.

- `make test`: 27 testów Swift i 4 testy pakowania, wszystkie zaliczone; dodatkowo test rzeczywistego AppModel z podstawianymi obserwacjami: awaria po połączeniu, timeout statusu, powrót do oczekiwania, spóźniony odczyt, monitorowanie podczas operacji, trwałość błędu i udana ponowna próba.
- `bash scripts/test-popover.sh`: wszystkie kontrole geometrii, zamykania, klawiatury i Settings zaliczone z Dockiem i bez.
- Render rzeczywistych widoków: awaria usługi, błąd operacji i połączenie, EN/PL, jasny/ciemny motyw.
- `make build`, weryfikacja podpisu ad-hoc, podmiana `/Applications/Tetherline.app` i ponowne uruchomienie wykonane. Końcowa diagnostyka: usługa niezainstalowana, socket nieobecny, integralność aplikacji poprawna. Testy nie uruchamiały silnika na telefonie.

Dodatkowo zweryfikowano rzeczywisty widok SwiftUI na bieżących odczytach systemowych (`bash scripts/render-previews.sh live`), bez włączania usługi: `registered=false`, `running=false`, `connected=false`. W EN/PL i obu motywach widok pokazuje wyłączoną usługę, Offline i przycisk włączenia. To osobny render tego samego kodu UI, nie zrzut pamięci już uruchomionego procesu. Zewnętrzny odczyt Accessibility nie jest dostępny (`AXIsProcessTrusted() == false`); wcześniejszego stanu UI sprzed restartu nie można tym odtworzyć.

## Quit zatrzymujący tethering — 17.11.2026

Dodano Quit w głównym panelu oraz Quit Tetherline w Settings. Przyciski, ⌘Q i żądanie zamknięcia z Docka przechodzą przez ten sam delegat AppKit. Przed zakończeniem aplikacja sprawdza aktualne zadanie launchd, konfigurację i proces chronionego helpera. Aktywna/zainstalowana usługa jest zatrzymywana istniejącą procedurą (bootout, oczekiwanie na koniec procesu, usunięcie plist); brak usługi pozwala wyjść bez administratora. Niepowodzenie lub anulowanie autoryzacji pozostawia UI otwarte. Ponowne żądanie Quit podczas operacji nie uruchamia drugiej operacji.

- `bash scripts/test-service-state.sh`: zaliczone, w tym opóźnione zatrzymanie, anulowanie autoryzacji, odrzucenie równoległego Quit i udana ponowna próba.
- `bash scripts/test-quit.sh`: zaliczony rzeczywisty cykl AppKit z kontrolowanym zatrzymaniem. Aplikacja pozostaje żywa do potwierdzenia zatrzymania, następnie kończy proces. Użyto asynchronicznego zatrzymania i ponownego wywołania terminate po sukcesie, aby uniknąć blokady MainActor w zagnieżdżonej pętli terminateLater.
- `bash scripts/test-popover.sh`: ponowne uruchomienie zaliczone (pierwsza próba przerwana na kontroli otwarcia panelu). Testy GUI używają podstawionej funkcji zakończenia, aby nie zatrzymywać rzeczywistej usługi.
- Render EN/PL w obu motywach: przycisk spójny z pozostałymi ActionButton.
- `make build` i weryfikacja ad-hoc zaliczone; build zainstalowano. Faktyczny proces z `/Applications` zakończył się po `NSRunningApplication.terminate()`, bez okna administratora przy nieobecnej usłudze. Potwierdzono brak procesu i zadania launchd. Natychmiastowy reopen trafił na chwilowy błąd Launch Services -600; kolejne wywołanie open ponownie uruchomiło aplikację.

## Sterowanie bez powtarzanej autoryzacji — 17.11.2026

Poprzednie Enable/Turn off/Quit wykonywały nowy AppleScript z uprawnieniami administratora. Upstream CLI ma odczyt statusu bez roota, ale `run`/`install`/`uninstall` wymagają roota; zainstalowana usługa pozostaje uruchomiona. Nowy kontroler usuwa potrzebę ponownej autoryzacji przy zwykłym sterowaniu GUI, bez hasła w aplikacji i bez zmian sudoers.

`TetherlineControl` jest chronioną kopią podpisaną ad-hoc i aktywowaną przez socket launchd. Weryfikuje peer UID z jądra, zezwala wyłącznie na konto instalujące (tu 501) i root, a protokół obejmuje tylko hello/start/stop dla skompilowanych ścieżek. Klient wymaga UID 0 serwera. Helper nie działa stale; kończy się po sekundzie bezczynności. Aktualizacja chronionych plików wykonywalnych i odinstalowanie nadal wymagają autoryzacji.

Wyniki:

- Dotychczasowe `make test` zaliczone (27 Swift, 4 pakowania, testy stanu/quit); dodatkowe 4 `ControlTests` zaliczone: konfiguracja on-demand, zamknięty zestaw poleceń, walidacja właściciela/sum i składni instalatora, poświadczenia socketu i limit wiadomości.
- Przygotowano `scripts/test-control.sh`; jeden autoryzowany skrypt przeprowadził izolowany test i dopiero po sukcesie zainstalował kontroler produkcyjny. W testach działał nieszkodliwy silnik, który tylko sprawdza UID 0 i czeka; muta/USB nie były uruchamiane.
- Konto UID 501 wykonało hello, start, ponowny start (ten sam PID), stop, ponowny stop, start i stop bez żadnej dodatkowej prośby o hasło. Silnik działał jako UID 0. Próby nieobsługiwanych poleceń i zbyt dużej wiadomości zostały odrzucone. Konto nobody zostało odrzucone. Helper zakończył proces po bezczynności i został ponownie aktywowany przez hello. Odinstalowanie usunęło wszystkie izolowane pliki, socket i usługi.
- Kontroler produkcyjny zainstalowany, owner UID 501, binarka root:wheel 0755 i plist root:wheel 0644. Zwykły użytkownik wykonał hello; SMAppService zgłasza enabled (1). W bezczynności launchd pokazuje `state = not running`. Sumy SHA-256 zainstalowanego kontrolera i silnika zgadzają się z paczką aplikacji.
- `make build`, weryfikacja podpisu i ponowny test cyklu zamknięcia AppKit zaliczone. Zainstalowano i uruchomiono nową `/Applications/Tetherline.app`. Końcowa diagnostyka: control helper installed=true, daemon installed=false, brak socketu muty. Nie włączano ponownie połączenia, które podczas pracy użytkownik wyłączył.

## Brak migającego błędu przy Turn off — 17.11.2026

Przyczyna: odpytywanie statusu co sekundę działało również podczas zatrzymywania. Skrypt najpierw wyładowuje zadanie launchd, czeka na koniec procesu, a dopiero potem usuwa plist. W tym oknie obserwacja widziała zainstalowaną, ale niedziałającą usługę i pokazywała „Unable to reach the service”. Analogiczne okno istnieje przy starcie (proces działa, zanim socket statusu jest gotowy).

Poprawka: na czas samego, nieinteraktywnego żądania start/stop (oraz zatrzymania przy Quit) odpytywanie jest wstrzymane, a odpowiedź z odpytywania będącego w toku jest odrzucana. Po starcie aplikacja czeka maksymalnie ~3 s na poprawny status przed pokazaniem wyniku. Prośby o autoryzację pozostają poza tym oknem, więc awaria w trakcie zatwierdzania nadal jest widoczna.

Wyniki: `make test` zaliczone (31 testów Swift, pakowanie, 9 testów stanu w tym 2 nowe: brak błędu podczas zatrzymywania i oczekiwanie na socket po starcie), `make build`, weryfikacja podpisu i test zamykania AppKit zaliczone. Nowa aplikacja zainstalowana w /Applications; SHA-256 silnika zgodne z chronioną kopią, więc Enable nie poprosi o hasło.

## Przebudowa sterowania i stanu — 18.11.2026

Powód: przegląd architektury po zgłoszeniu migającego błędu przy Turn off. Interfejs zgadywał stan usługi co sekundę z kilku poleceń, również podczas własnych operacji, więc widział stany pośrednie jako awarie. Każde Enable instalowało usługę od nowa, a Turn off ją usuwał. Helper nie miał ścieżki aktualizacji.

Zmiany:

- Konfiguracja usługi muty jest instalowana na stałe. Enable i Turn off przełączają ją przez `launchctl enable/disable` i bootstrap/bootout. Przełącznik decyduje też o starcie po restarcie systemu.
- Jeden instalator dla instalacji i aktualizacji doprowadza system do stanu paczki i zmienia tylko różnice. Aplikacja wykrywa nieaktualne komponenty po SHA-256 i treści plistów; tylko wtedy Enable prosi o hasło. Dotychczasowy układ (brak plistu po Turn off) jest migrowany i pozostaje wyłączony.
- Helper ma polecenia `start` i `stop`, wykonywane w Swift bez powłoki. Start kończy się, gdy muta odpowiada, a stop, gdy proces zniknął. Błędy mają stałe kody, które aplikacja tłumaczy. Helper kompiluje się tylko z potrzebnych plików.
- Stan czyta aplikacja bez roota, tym samym kodem co helper: `launchd` jest źródłem prawdy o naszym silniku, a inna muta jest rozpoznawana po ścieżce programu w trybie `run`. Podczas operacji aplikacja nie odczytuje stanu, tylko pokazuje Włączanie…/Wyłączanie…. Wynik publikuje przed zakończeniem operacji. Odczyt co sekundę przy widocznym panelu lub oknie, co pięć sekund w tle.
- Interfejs renderuje jeden jawny stan (ServicePhase) zamiast kilkunastu flag.
- Usunięto migrację ze starej instalacji muty i alias w `~/.zshrc` (decyzja użytkownika). Inna działająca muta jest nadal wykrywana jako konflikt.
- Polecenia czekają na zakończenie procesu sygnałem zamiast aktywnej pętli i nie blokują wątków puli współbieżności.

Wyniki:

- `make test` zaliczone: 43 testy jednostkowe (m.in. odczyt stanu, fazy, porównanie instalacji, skrypty, protokół z odpowiedziami poprzedniego helpera), pakowanie, 8 testów modelu. Test „turning off” odtwarza zgłoszony błąd: podczas Turn off nie ma żadnego odczytu, a stan przechodzi z Wyłączanie… prosto do wyłączonego.
- Testy GUI zamykania, panelu, widoczności i LaunchAgenta zaliczone. Podglądy wszystkich stanów EN/PL sprawdzone.
- `scripts/test-control.sh --install-production`: 15 kroków na izolowanej usłudze z atrapą silnika zaliczonych (zła suma, dowiązanie, instalacja, idempotencja, aktualizacja bez restartu i z restartem, start/stop bez hasła, przełącznik startu po restarcie, konflikt, migracja układu, aktywacja na żądanie, inne konto, odinstalowanie). Następnie zaktualizowano instalację produkcyjną.
- Pierwszy przebieg wykrył błąd: świeżo uruchomiony silnik był brany za inną mutę (dwa odczyty w różnych chwilach, porównanie PID). Poprawione na rozróżnianie po ścieżce.
- Drugi przebieg zawiesił się na kroku konfliktu: powłoka uruchomiona przez autoryzację ignoruje SIGTERM, a atrapa to dziedziczyła. Test używa teraz SIGKILL. Autoryzacja `do shell script` była zapamiętana, więc kolejne przebiegi nie pokazywały okna hasła. Proces roota nie jest dzieckiem `osascript`, tylko `authtrampoline`. Zawieszony przebieg posprzątano jednorazowym skryptem w tej samej autoryzacji co końcowy test; produkcja nie była wcześniej zmieniana.
- Stan końcowy: helper i silnik identyczne z paczką, plist usługi zainstalowany, `pl.tetherline.muta => disabled`, usługa niezaładowana, helper w bezczynności nie działa. Nowa `/Applications/Tetherline.app` zainstalowana; `--diagnose`: installation current, loaded=false, conflict=false, stan „Tethering is off”. Tethering pozostawiono wyłączony, zgodnie z wyborem użytkownika.
- Nie sprawdzono: cyklu z prawdziwą mutą i telefonem po przebudowie oraz restartu Maca z włączonym i wyłączonym tetheringiem.

Kopia źródeł sprzed przebudowy: `~/Projects/tetherline-backup-20261117-pre-refactor.tar.gz`.
