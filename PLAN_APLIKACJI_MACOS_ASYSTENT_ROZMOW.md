# Plan przygotowania aplikacji macOS do wsparcia rozmow live

## 1. Cel aplikacji

Aplikacja ma dzialac jako prywatny asystent podczas rozmow rekrutacyjnych, rozmow z klientem i live codingu. Uzytkownik ma widziec dyskretny overlay na macOS, ktory:

- transkrybuje rozmowe w czasie zblizonym do rzeczywistego,
- rozroznia wypowiedzi uzytkownika i rozmowcy,
- wykrywa pytania lub wazne watki rozmowy,
- generuje propozycje odpowiedzi przez model OpenAI,
- na skrot klawiszowy przechwytuje aktualny kod z ekranu i sugeruje rozwiazanie,
- pozostaje widoczny tylko dla uzytkownika w mozliwie najwiekszym zakresie technicznym.

Wazne zalozenie: macOS i aplikacje typu Teams, Google Meet, Discord, Zoom roznie implementuja udostepnianie ekranu. Nie mozna obiecac stuprocentowej niewidocznosci overlayu we wszystkich trybach screen share. Trzeba to potraktowac jako wymaganie testowane per tryb: udostepnianie okna, udostepnianie calego ekranu, udostepnianie karty przegladarki, nagrywanie przez aplikacje trzecie.

## 2. Rekomendowany stack technologiczny

### Aplikacja desktopowa

Rekomendacja: natywna aplikacja macOS.

- Swift 6
- SwiftUI do glownego UI
- AppKit dla niestandardowego overlayu, okien zawsze-na-wierzchu, hotkeyow i integracji systemowych
- Combine lub Swift Concurrency do obslugi strumieni audio, OCR i zapytan AI
- Xcode jako glowne srodowisko

Alternatywa: Electron lub Tauri. Nie rekomenduje jako pierwszego wyboru, bo aplikacja potrzebuje glebokich integracji z macOS: audio, screen capture, permissions, overlay, global shortcuts. Natywny Swift bedzie stabilniejszy.

### Audio

- AVFoundation do mikrofonu uzytkownika
- ScreenCaptureKit do przechwytywania audio z aplikacji lub wybranego zrodla, tam gdzie system na to pozwala
- CoreAudio do niskopoziomowego routingu i monitorowania urzadzen
- AudioDriverKit jako pozniejszy etap, jesli potrzebny bedzie wirtualny sterownik audio podobny do BlackHole/Loopback

MVP powinno najpierw uzyc prostszego wariantu:

- mikrofon jako kanal "ja",
- system/app audio jako kanal "rozmowca",
- konfiguracja uzytkownika w onboardingu, ktore zrodlo audio ma byc przechwytywane.

### Transkrypcja i AI

- OpenAI Realtime API albo streaming transkrypcji + model tekstowy
- Whisper/OpenAI audio transcription jako fallback lub tryb nizszego kosztu
- lokalny VAD, czyli voice activity detection, do wykrywania fragmentow mowy
- kolejka zdarzen rozmowy: wypowiedz, pytanie, decyzja, follow-up, kod, notatka

W praktyce warto rozdzielic:

- szybka transkrypcja live,
- detekcja pytan i intencji,
- generowanie krotkich podpowiedzi,
- generowanie dluzszej odpowiedzi dopiero na zyczenie uzytkownika.

### Przechwytywanie kodu z ekranu

- globalny shortcut przez AppKit/EventTap
- ScreenCaptureKit lub CGWindowListCreateImage do zrzutu aktywnego okna/obszaru
- OCR: Apple Vision Framework jako pierwszy wybor
- opcjonalnie integracja z Accessibility API do odczytu tekstu z aktywnej aplikacji, jesli edytor/IDE to wspiera
- fallback: schowek, czyli uzytkownik zaznacza kod i wciska skrot, aplikacja pobiera tekst z clipboardu

Dla live codingu najlepszy UX:

- `Cmd + Shift + Space`: pokaz/ukryj overlay,
- `Cmd + Shift + C`: przechwyc kod z aktywnego okna lub schowka,
- `Cmd + Shift + A`: wygeneruj odpowiedz na ostatnie pytanie,
- `Cmd + Shift + N`: zapisz notatke z aktualnego watku.

### Backend

Na start nie budowac ciezkiego backendu.

MVP:

- aplikacja macOS komunikuje sie bezposrednio z OpenAI API,
- klucz API przechowywany lokalnie w Keychain,
- lokalna historia sesji w SQLite.

Wersja produkcyjna:

- backend w Node.js/NestJS albo Python/FastAPI,
- autoryzacja uzytkownikow,
- billing,
- szyfrowane przechowywanie sesji,
- proxy do OpenAI API,
- panel administracyjny i limity uzycia.

### Lokalna baza danych

- SQLite
- GRDB.swift albo SQLite.swift
- Keychain do sekretow
- opcjonalnie SQLCipher, jesli historia rozmow ma byc szyfrowana na dysku

## 3. Architektura aplikacji

Proponowane moduly:

- `Overlay`: prywatne okno z podpowiedziami, tryb kompaktowy i rozszerzony.
- `Permissions`: mikrofon, screen recording, accessibility, automation.
- `AudioCapture`: pobieranie mikrofonu i audio rozmowcy.
- `AudioSeparation`: oznaczanie kanalow "ja" i "rozmowca".
- `Transcription`: streaming audio do transkrypcji.
- `ConversationEngine`: laczenie wypowiedzi w kontekst rozmowy.
- `QuestionDetector`: wykrywanie pytan i momentow, w ktorych warto podpowiedziec odpowiedz.
- `SuggestionEngine`: generowanie odpowiedzi przez OpenAI.
- `CodeCapture`: screenshot, OCR, clipboard, aktywne okno.
- `CodingAssistant`: analiza kodu, propozycje zmian, wyjasnienia.
- `SessionStore`: lokalna historia sesji, notatki, ustawienia.
- `PrivacyGuard`: kontrola widocznosci overlayu, tryb ukryty, czyszczenie danych.

## 4. Ograniczenia techniczne, ktore trzeba sprawdzic na poczatku

### Widocznosc overlayu podczas udostepniania ekranu

Do przetestowania:

- Teams: udostepnianie calego ekranu,
- Teams: udostepnianie okna,
- Google Meet w Chrome: udostepnianie ekranu,
- Google Meet: udostepnianie karty,
- Discord: screen share,
- Zoom: screen share.

Mozliwe techniki:

- okno overlay bez tytulu, przezroczyste, zawsze na wierzchu,
- AppKit `NSPanel` lub niestandardowy `NSWindow`,
- odpowiednie `collectionBehavior`, np. obecnosc na wszystkich Spaces,
- wykluczanie okna z listy okien tam, gdzie macOS/API na to pozwala,
- tryb alternatywny: overlay na drugim monitorze,
- tryb alternatywny: podpowiedzi w menu bar / mini panelu / iPhone companion app.

Nie nalezy opierac produktu w 100% na zalozeniu, ze overlay zawsze bedzie niewidoczny przy udostepnianiu calego ekranu.

### Audio z aplikacji rozmowy

Do przetestowania:

- czy ScreenCaptureKit pozwala stabilnie pobrac audio z wybranej aplikacji,
- jak rozroznic mikrofon uzytkownika i audio rozmowcy,
- opoznienie transkrypcji,
- echo i nakladanie sie glosow,
- sluchawki Bluetooth vs kabel vs glosniki.

Jesli proste podejscie nie wystarczy, etap 2 powinien zawierac wirtualne urzadzenie audio.

### Uprawnienia macOS

Aplikacja bedzie potrzebowala:

- Microphone,
- Screen Recording,
- Accessibility,
- Input Monitoring dla globalnych skrotow, jesli wymagane,
- ewentualnie System Extension dla sterownika audio.

Onboarding musi jasno przeprowadzic uzytkownika przez nadawanie tych uprawnien.

## 5. Plan prac

### Etap 0: walidacja techniczna

Cel: sprawdzic, czy najtrudniejsze elementy sa wykonalne przed budowaniem pelnego produktu.

Zadania:

1. Utworzyc minimalna aplikacje macOS w SwiftUI.
2. Dodac floating overlay jako `NSPanel`.
3. Sprawdzic, czy overlay pojawia sie lub nie pojawia w screen share w Teams, Meet, Discord i Zoom.
4. Dodac przechwytywanie mikrofonu.
5. Dodac przechwytywanie audio z wybranej aplikacji lub ekranu przez ScreenCaptureKit.
6. Wyslac krotki fragment audio do transkrypcji.
7. Zmierzyc opoznienie od wypowiedzi do tekstu.
8. Dodac pierwszy globalny shortcut.
9. Zrobic screenshot aktywnego okna i OCR kodu przez Vision.

Efekt etapu:

- raport techniczny: co dziala, co nie dziala, jakie sa ograniczenia,
- decyzja, czy MVP da sie zrobic bez wirtualnego sterownika audio.

### Etap 1: MVP lokalne

Cel: aplikacja uzywalna przez jedna osobe lokalnie, bez logowania i backendu.

Funkcje:

- overlay z trzema sekcjami: ostatnie pytanie, sugerowana odpowiedz, kontekst rozmowy,
- transkrypcja mikrofonu i rozmowcy,
- detekcja pytan rozmowcy,
- automatyczna sugestia odpowiedzi,
- reczne wygenerowanie odpowiedzi skrotem klawiszowym,
- przechwycenie kodu ze schowka lub screenshotu,
- analiza kodu przez model,
- lokalna historia sesji,
- ustawienia modelu, jezyka i skrotow.

Technicznie:

- SwiftUI + AppKit,
- OpenAI API,
- SQLite,
- Keychain,
- Vision OCR,
- AVFoundation,
- ScreenCaptureKit.

### Etap 2: poprawa jakosci rozmow live

Cel: zmniejszyc opoznienia i poprawic jakosc podpowiedzi.

Funkcje:

- streaming transkrypcji,
- wykrywanie aktywnego mowcy,
- inteligentne laczenie wypowiedzi w watki,
- tryb "odpowiedz krotko", "odpowiedz technicznie", "odpowiedz biznesowo",
- tryb rozmowy rekrutacyjnej,
- tryb rozmowy z klientem,
- tryb negocjacji/obiekcji,
- przycisk "nie podpowiadaj do tego watku",
- automatyczne notatki po rozmowie.

### Etap 3: live coding assistant

Cel: aplikacja realnie pomaga podczas zadan technicznych.

Funkcje:

- odczyt kodu ze zrzutu ekranu,
- odczyt kodu ze schowka,
- analiza bledu widocznego w terminalu,
- wykrywanie jezyka programowania,
- sugestia nastepnego kroku,
- generowanie odpowiedzi werbalnej typu "jak to wyjasnic rekruterowi",
- tryb bez wklejania gotowego kodu, tylko wskazowki,
- historia przechwyconych fragmentow kodu w ramach sesji.

### Etap 4: wersja produkcyjna

Cel: przygotowanie produktu dla wielu uzytkownikow.

Funkcje:

- konta uzytkownikow,
- plany platnosci,
- backend proxy do OpenAI,
- limity uzycia,
- synchronizacja ustawien,
- szyfrowanie danych,
- crash reporting,
- auto-update aplikacji,
- podpisywanie i notarization Apple.

Technologie:

- FastAPI albo NestJS,
- PostgreSQL,
- Stripe,
- Sentry,
- Sparkle do aktualizacji aplikacji macOS,
- Apple Developer ID signing + notarization.

## 6. Proponowana struktura repozytorium

```text
macos-interview-assistant/
  apps/
    macos/
      InterviewAssistant.xcodeproj
      InterviewAssistant/
        App/
        Overlay/
        Audio/
        Transcription/
        Conversation/
        Suggestions/
        CodeCapture/
        Storage/
        Permissions/
  backend/
    api/
  docs/
    research/
    architecture/
    product/
  scripts/
```

Dla samego MVP mozna zaczac prosciej:

```text
InterviewAssistant/
  InterviewAssistant.xcodeproj
  InterviewAssistant/
  docs/
```

## 7. UX aplikacji

Glowne zalozenie: aplikacja nie moze przeszkadzac w rozmowie.

Widoki:

- mini overlay: 1-2 linie podpowiedzi,
- pelny overlay: pytanie, odpowiedz, kontekst, akcje,
- panel sesji: historia, notatki, zapis rozmowy,
- ustawienia: klucz API, model, jezyk, skroty, audio, prywatnosc.

Zasady:

- brak duzych modalow podczas rozmowy,
- mozliwosc natychmiastowego ukrycia overlayu,
- czytelny tekst na malym panelu,
- odpowiedzi generowane w punktach,
- domyslnie krotkie sugestie, bez dlugich elaboratow.

## 8. Bezpieczenstwo i prywatnosc

To jest aplikacja przetwarzajaca wrazliwe dane z rozmow, wiec trzeba zaprojektowac ja konserwatywnie.

Wymagania:

- jasna informacja, kiedy audio jest nagrywane/przetwarzane,
- lokalne przechowywanie klucza API w Keychain,
- opcja "nie zapisuj historii",
- opcja usuniecia sesji jednym kliknieciem,
- szyfrowanie lokalnej bazy w wersji produkcyjnej,
- minimalizacja wysylanych danych do modelu,
- brak wysylania calej historii, jesli wystarczy ostatni kontekst,
- osobny tryb dla rozmow poufnych.

Warto tez przygotowac regulaminowy disclaimer: uzytkownik odpowiada za zgodnosc uzycia aplikacji z zasadami rozmowy, firmy, klienta i prawem lokalnym.

## 9. Ryzyka

Najwieksze ryzyka:

- overlay moze byc widoczny w niektorych trybach screen share,
- przechwytywanie audio z konkretnej aplikacji moze byc niestabilne,
- rozdzielenie mowcow moze dzialac gorzej przy echu lub slabym mikrofonie,
- opoznienie AI moze byc za duze dla naturalnej rozmowy,
- aplikacje typu Teams/Meet/Discord moga zmieniac zachowanie po aktualizacjach,
- produkt ma wysokie wymagania prywatnosci i moze byc kontrowersyjny w niektorych zastosowaniach.

Sposob ograniczenia ryzyka:

- najpierw proof of concept overlay + audio,
- testy na realnych callach,
- tryb manualny zamiast pelnej automatyzacji,
- jasna konfiguracja zrodel audio,
- fallback przez clipboard i reczne skroty,
- brak obietnicy pelnej niewidocznosci overlayu.

## 10. Kolejnosc pierwszych zadan

1. Stworzyc projekt SwiftUI macOS.
2. Dodac overlay `NSPanel` z testowym tekstem.
3. Dodac hotkey pokaz/ukryj.
4. Przetestowac overlay na Teams, Meet, Discord, Zoom.
5. Dodac przechwytywanie mikrofonu.
6. Dodac transkrypcje jednego kanalu audio.
7. Dodac integracje z OpenAI do generowania odpowiedzi z tekstu.
8. Dodac prosty panel ustawien z kluczem API w Keychain.
9. Dodac screenshot aktywnego okna.
10. Dodac OCR kodu.
11. Dodac prompt do analizy kodu.
12. Dodac lokalna historie sesji.
13. Przygotowac testy opoznienia i jakosci odpowiedzi.
14. Dopiero potem decydowac, czy potrzebny jest wirtualny sterownik audio.

## 11. Dokumentacja techniczna do sprawdzenia

- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Apple AudioDriverKit: https://developer.apple.com/documentation/audiodriverkit
- Apple AppKit NSWindow: https://developer.apple.com/documentation/appkit/nswindow
- Apple Vision Framework: https://developer.apple.com/documentation/vision
- OpenAI API docs: https://platform.openai.com/docs

## 12. Definicja MVP

MVP uznajemy za gotowe, gdy:

- aplikacja uruchamia sie lokalnie na macOS,
- uzytkownik widzi prywatny overlay,
- dziala globalny skrot pokaz/ukryj,
- dziala transkrypcja rozmowy przynajmniej z jednego zrodla audio,
- mozna wygenerowac odpowiedz na ostatnie pytanie,
- mozna przechwycic kod ze schowka lub screenshotu,
- aplikacja generuje sugestie dotyczace kodu,
- historia sesji zapisuje sie lokalnie,
- przetestowano zachowanie overlayu w minimum Teams i Google Meet.
