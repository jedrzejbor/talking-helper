# Etap 0: start projektu macOS i testy techniczne

## Cel etapu

Etap 0 ma sprawdzic najwieksze ryzyka techniczne przed budowa pelnej aplikacji:

- czy da sie zrobic prywatny overlay widoczny dla uzytkownika,
- jak overlay zachowuje sie podczas screen share w Teams, Google Meet, Discord i Zoom,
- czy aplikacja moze przechwytywac mikrofon,
- czy aplikacja moze przechwytywac audio z rozmowy lub z systemu,
- czy da sie zrobic globalne skroty klawiszowe,
- czy da sie przechwycic kod z aktywnego okna lub schowka,
- czy OCR z Apple Vision wystarczy do live codingu,
- jakie jest realne opoznienie transkrypcji i odpowiedzi AI.

Na koniec Etapu 0 powinnismy miec dzialajacy proof of concept oraz liste ograniczen.

## Wymagania lokalne

Potrzebne:

- macOS 14 Sonoma lub nowszy; najlepiej macOS 15+,
- Xcode 16 lub nowszy,
- konto Apple Developer, jesli bedziemy testowac podpisywanie, notarization albo bardziej zaawansowane uprawnienia,
- konto OpenAI API,
- Teams, Google Chrome, Discord i opcjonalnie Zoom do testow screen share,
- sluchawki z mikrofonem do testow audio.

Sprawdzenie wersji:

```bash
sw_vers
xcodebuild -version
```

## Utworzenie projektu w Xcode

1. Otworz Xcode.
2. Wybierz `File > New > Project`.
3. Wybierz `macOS > App`.
4. Ustaw:
   - `Product Name`: `InterviewAssistant`
   - `Team`: Twoje konto developerskie albo `None` na start
   - `Organization Identifier`: np. `com.local`
   - `Interface`: `SwiftUI`
   - `Language`: `Swift`
   - `Use Core Data`: off
   - `Include Tests`: on
5. Zapisz projekt w tym katalogu:

```text
/Users/jedrek/Desktop/aplikacja do rozmow rekrutacyjnych
```

Docelowa struktura po utworzeniu:

```text
aplikacja do rozmow rekrutacyjnych/
  InterviewAssistant/
    InterviewAssistant.xcodeproj
    InterviewAssistant/
    InterviewAssistantTests/
    InterviewAssistantUITests/
  PLAN_APLIKACJI_MACOS_ASYSTENT_ROZMOW.md
  ETAP_0_START_PROJEKTU_I_TESTY.md
```

Jesli Xcode utworzy projekt bez dodatkowego katalogu `InterviewAssistant/`, to tez jest akceptowalne. Wazne, zeby nie mieszac plikow aplikacji z dokumentacja bardziej niz to konieczne.

## Konfiguracja projektu

W `Signing & Capabilities`:

- wlacz `App Sandbox` na start,
- dodaj `Audio Input`, jesli sandbox jest wlaczony,
- sprawdz, czy aplikacja ma poprawny `Bundle Identifier`, np. `com.local.InterviewAssistant`.

W `Info.plist` trzeba dodac opisy uprawnien:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Aplikacja potrzebuje mikrofonu do transkrypcji Twoich wypowiedzi podczas rozmowy.</string>
<key>NSScreenCaptureUsageDescription</key>
<string>Aplikacja potrzebuje dostepu do ekranu, aby przechwytywac kod i testowac overlay.</string>
```

Uwaga: czesc uprawnien, np. Screen Recording i Accessibility, uzytkownik nadaje recznie w:

```text
System Settings > Privacy & Security
```

## Minimalny zakres proof of concept

Etap 0 powinien miec 5 malych ekranow lub modulow testowych:

- `Overlay Test`: pokazanie/ukrycie overlayu.
- `Hotkey Test`: globalny skrot pokaz/ukryj.
- `Microphone Test`: poziom glosnosci mikrofonu i zapis kilku sekund audio.
- `Screen/OCR Test`: screenshot aktywnego okna albo wybranego obszaru i OCR.
- `AI Test`: wyslanie tekstowego pytania do OpenAI i pokazanie odpowiedzi.

Nie budujemy jeszcze pelnej aplikacji. Chodzi o walidacje techniczna.

## Proponowane moduly kodu dla Etapu 0

```text
InterviewAssistant/
  App/
    InterviewAssistantApp.swift
    ContentView.swift
  Overlay/
    OverlayPanelController.swift
    OverlayView.swift
  Hotkeys/
    HotkeyManager.swift
  Permissions/
    PermissionsView.swift
    PermissionChecker.swift
  Audio/
    MicrophoneCaptureService.swift
    AudioLevelMeter.swift
  ScreenCapture/
    ScreenshotService.swift
    OCRService.swift
  AI/
    OpenAIClient.swift
    PromptBuilder.swift
  Diagnostics/
    DiagnosticsStore.swift
```

W Etapie 0 mozna trzymac implementacje prosto. Refaktoryzacja przyjdzie dopiero po potwierdzeniu, ktore API dzialaja stabilnie.

## Uruchamianie aplikacji

### Z Xcode

Najprostszy sposob:

1. Otworz `InterviewAssistant.xcodeproj`.
2. Wybierz scheme `InterviewAssistant`.
3. Wybierz destination `My Mac`.
4. Kliknij `Run`.

Przy pierwszym uruchomieniu macOS powinien zapytac o mikrofon. Screen Recording i Accessibility czesto trzeba nadac recznie.

### Z terminala

Po utworzeniu projektu mozna budowac go tak:

```bash
cd "/Users/jedrek/Desktop/aplikacja do rozmow rekrutacyjnych/InterviewAssistant"
xcodebuild -scheme InterviewAssistant -destination 'platform=macOS' build
```

Testy jednostkowe:

```bash
cd "/Users/jedrek/Desktop/aplikacja do rozmow rekrutacyjnych/InterviewAssistant"
xcodebuild test -scheme InterviewAssistant -destination 'platform=macOS'
```

Jesli Xcode utworzy projekt w innej strukturze, trzeba dostosowac `cd` do lokalizacji pliku `.xcodeproj`.

## Zmienne i sekrety

Na Etapie 0 sa dwie opcje.

Opcja prosta:

- wpisywanie klucza OpenAI w polu tekstowym w aplikacji,
- zapis do macOS Keychain,
- brak commita klucza do repozytorium.

Opcja tymczasowa tylko do lokalnych testow:

```bash
export OPENAI_API_KEY="..."
```

Nie dodajemy klucza API do plikow `.swift`, `.plist`, `.xcconfig` ani do dokumentacji.

## Test 1: overlay

Cel: sprawdzic, czy mozna pokazac mala prywatna warstwe nad innymi aplikacjami.

Zakres:

- okno bez standardowego paska tytulu,
- stale na wierzchu,
- mozliwosc przesuwania,
- przezroczyste tlo albo ciemny kompaktowy panel,
- przycisk zamkniecia lub skrot ukrycia,
- widocznosc na roznych Spaces.

Kryterium zaliczenia:

- overlay pokazuje sie nad Chrome, Teams, Discord i Xcode,
- da sie go ukryc natychmiast skrotem,
- overlay nie kradnie stale focusu z aktywnej aplikacji.

## Test 2: overlay podczas screen share

Cel: sprawdzic realne zachowanie w aplikacjach do rozmow.

Macierz testow:

| Aplikacja | Tryb | Czy overlay widac u rozmowcy? | Uwagi |
| --- | --- | --- | --- |
| Teams | caly ekran | do sprawdzenia |  |
| Teams | konkretne okno | do sprawdzenia |  |
| Google Meet | caly ekran | do sprawdzenia | Chrome |
| Google Meet | karta | do sprawdzenia | Chrome |
| Discord | ekran | do sprawdzenia |  |
| Discord | aplikacja | do sprawdzenia |  |
| Zoom | ekran | do sprawdzenia | opcjonalnie |
| Zoom | okno | do sprawdzenia | opcjonalnie |

Kryterium zaliczenia:

- mamy zapisane wyniki dla minimum Teams i Google Meet,
- wiemy, ktory tryb udostepniania jest akceptowalny dla MVP,
- jesli overlay jest widoczny przy udostepnianiu calego ekranu, dokumentujemy to jako ograniczenie produktu.

## Test 3: mikrofon

Cel: potwierdzic, ze aplikacja moze pobierac glos uzytkownika.

Zakres:

- prosba o uprawnienie mikrofonu,
- prosty miernik poziomu audio,
- wykrywanie ciszy i mowy,
- zapis krotkiego fragmentu testowego tylko lokalnie,
- wyswietlenie statusu: `listening`, `speech detected`, `silent`, `permission missing`.

Kryterium zaliczenia:

- aplikacja widzi mikrofon,
- poziom audio reaguje na glos,
- brak crasha po odlaczeniu lub zmianie mikrofonu.

## Test 4: audio rozmowcy

Cel: sprawdzic, czy da sie pobrac audio z aplikacji rozmowy lub audio systemowe.

Warianty do sprawdzenia:

- ScreenCaptureKit z wybranym zrodlem,
- przechwycenie audio ekranu/aplikacji, jesli dostepne,
- fallback przez wirtualne urzadzenie audio w pozniejszym etapie.

Kryterium zaliczenia:

- potrafimy uzyskac osobny strumien dla mikrofonu i osobny dla rozmowcy albo wiemy, ze bez wirtualnego urzadzenia bedzie to niestabilne,
- znamy opoznienie i jakosc nagrania,
- wiemy, czy sluchawki Bluetooth pogarszaja wynik.

## Test 5: transkrypcja

Cel: sprawdzic opoznienie od wypowiedzi do tekstu.

Zakres:

- wyslanie krotkiego fragmentu audio do transkrypcji,
- wyswietlenie tekstu w aplikacji,
- zapis czasu: start mowy, koniec mowy, otrzymanie transkrypcji,
- test po polsku i angielsku.

Kryterium zaliczenia:

- transkrypcja dziala dla prostego zdania,
- opoznienie jest zmierzone,
- mamy decyzje, czy MVP robi streaming, czy najpierw tryb fragmentami.

## Test 6: AI odpowiedzi tekstowe

Cel: potwierdzic integracje z OpenAI bez audio.

Zakres:

- pole tekstowe `Pytanie rozmowcy`,
- przycisk `Wygeneruj odpowiedz`,
- wyswietlenie krotkiej odpowiedzi w overlayu,
- obsluga bledu API,
- timeout,
- brak zapisu klucza API poza Keychain.

Kryterium zaliczenia:

- aplikacja generuje odpowiedz na pytanie tekstowe,
- blad API jest pokazany czytelnie,
- odpowiedz miesci sie w overlayu.

## Test 7: screenshot i OCR kodu

Cel: sprawdzic, czy mozemy pobrac kod widoczny na ekranie.

Zakres:

- globalny skrot `Cmd + Shift + C`,
- pobranie tekstu ze schowka, jesli jest dostepny,
- jesli schowek pusty: screenshot aktywnego okna lub wskazanego obszaru,
- OCR przez Vision,
- pokazanie rozpoznanego tekstu,
- wyslanie rozpoznanego kodu do AI z prosba o analize.

Kryterium zaliczenia:

- clipboard path dziala poprawnie,
- OCR dziala przynajmniej dla duzego fontu w Xcode/VS Code,
- aplikacja potrafi wygenerowac sugestie dotyczaca kodu.

## Test 8: globalne skroty

Proponowane skroty na Etap 0:

- `Cmd + Shift + Space`: pokaz/ukryj overlay,
- `Cmd + Shift + A`: wygeneruj odpowiedz na ostatnie pytanie,
- `Cmd + Shift + C`: przechwyc kod,
- `Cmd + Shift + X`: wyczysc overlay.

Kryterium zaliczenia:

- skroty dzialaja, gdy aktywna jest inna aplikacja,
- skroty nie konfliktuja z Xcode, Chrome, Teams i Discord,
- aplikacja potrafi pokazac instrukcje, jesli brakuje uprawnien.

## Checklista realizacji Etapu 0

- [ ] Utworzony projekt `InterviewAssistant` w Xcode.
- [ ] Projekt buduje sie lokalnie.
- [ ] Dziala podstawowe okno SwiftUI.
- [x] Dziala overlay `NSPanel`.
- [ ] Dziala skrot pokaz/ukryj.
- [ ] Dziala wykrywanie uprawnien.
- [ ] Dziala mikrofon i miernik poziomu.
- [ ] Przetestowano screen share w Teams.
- [ ] Przetestowano screen share w Google Meet.
- [ ] Przetestowano przechwytywanie audio rozmowcy.
- [ ] Dziala transkrypcja testowego audio.
- [ ] Dziala tekstowa integracja z OpenAI.
- [ ] Dziala clipboard capture dla kodu.
- [ ] Dziala OCR screenshotu.
- [ ] Spisano ograniczenia i decyzje do MVP.

## Wyniki testow

Ten fragment uzupelniamy po testach.

| Obszar | Status | Wynik | Decyzja |
| --- | --- | --- | --- |
| Overlay lokalnie | nie testowano |  |  |
| Overlay Teams | nie testowano |  |  |
| Overlay Google Meet | nie testowano |  |  |
| Overlay Discord | nie testowano |  |  |
| Mikrofon | nie testowano |  |  |
| Audio rozmowcy | nie testowano |  |  |
| Transkrypcja | nie testowano |  |  |
| OpenAI tekst | nie testowano |  |  |
| Screenshot/OCR | nie testowano |  |  |
| Hotkeys | nie testowano |  |  |

## Decyzje po Etapie 0

Po zakonczeniu etapu trzeba odpowiedziec na pytania:

1. Czy overlay jest wystarczajaco prywatny dla MVP?
2. Ktore tryby screen share sa wspierane, a ktore nie?
3. Czy audio rozmowcy da sie pobrac bez wirtualnego sterownika?
4. Czy transkrypcja ma akceptowalne opoznienie?
5. Czy OCR jest wystarczajacy, czy MVP powinno opierac sie glownie na schowku?
6. Czy zaczynamy Etap 1 w obecnej architekturze, czy najpierw robimy dodatkowy proof of concept audio?
