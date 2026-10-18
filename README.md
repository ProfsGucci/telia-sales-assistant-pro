# Telia Sales Assistant Pro

**Personligt säljverktyg för anställda hos Telia Sverige — native SwiftUI för
iPhone och iPad, allt lokalt på din enhet.**

> ⚠️ **Viktigt omwändare:** det här är ett oberoende personligt verktyg, **inte**
> en officiell Telia-produkt och inte kopplat till Telias system. Priser läses
> in från offentliga sidor på telia.se och kan aldrig garanteras vara aktuella —
> verifiera alltid mot källan (varje produkt visar källänk + kontrolltidpunkt).

---

## Vad appen gör

| Område | Funktioner |
|---|---|
| **Hem** | personlig dashboard: nästa pass, checklista, målringar, Kampanj Center-kort, kampanj-i-fokus, snabbsök, dagens tips, mini-quiz, senast visade produkter, prisfräschhet, anpassningsbar ordning |
| **Kampanj Center** | kampanjer verifierade mot offentliga telia.se-sidor: kort med pris (månads-/engångspris hålls isär), ordinarie pris, besparing endast när jämförbart, bindningstid, villkor, källa + verifieringstid. Detaljvy, jämför upp till 3, sök/filter/sortering, favoriter, senast visade, "slutar snart"-hantering, utgångna visas aldrig som aktiva |
| **Produkter** | verifierad pris-/produktkatalog med sök, filter, sortering, jämför upp till 3, total-/snittkostnad per bindningstid, kampanjpris & slutdatum |
| **Räknare** | abonnemangstotalkostnad, enhet+abonnemang (kontant vs delbetalning), familjeräknare, kampanjutgång — allt mot inläst katalogdata |
| **AI-coach** | chatt med svensk, produkt- och kampanjförankrad coach. Echtd streaming mot egen OpenAI-kompatibel server; **demoläge tydligt märkt** när ingen server konfigurerats. Historik, källhänvisningar, försök-igen |
| **Kalender** | månad/vecka/kommande, pass & uppgifter, återkommande händelser, valfri export till Apple Calendar (fungerar utan behörighet), lokala påminnelser 30 min före pass |
| **Min utveckling** | manuella passloggar (appens hittar **aldrig** på siffror), Swift Charts-grafer, mål vs utfall, personliga förslag, träningsstatistik |
| **Säljmanus** | spelbok med 6-delad objectionsstruktur, redigerbara manus |
| **Rollspel** | kundsimulator med svårighetsgrad, 9-dimensionell bedömning — belönar aldrig påtryckningstaktik |
| **Akademin** | lektioner, quiz, flashcards med intervallrepetition, streak, svaga områden, 30-dagarsprogram |
| **Bibliotek** | favoriter, manus, anteckningar, sparade coachsvar, ordlista, källista |
| **Inställningar** | tema, **egen bakgrund** (förinställda gradienter, egen färg, egen bild från PhotosPicker — allt lokalt), kampanjfeed-URL, prisfeed-URL, AI-backend (nyckel i Keychain), import/export, radera allt |

## Projektstruktur

```
TeliaSalesAssistantPro.xcodeproj     genererat av tools/gen_pbxproj.py (deterministiskt)
TeliaSalesAssistantPro/
  App/               @main, root (iPhone tabs / iPad split view)
  Features/          Home, Products, Coach, Playbook, RolePlay, Academy,
                     Calendar, Progress, Library, Settings
  Services/          DataStore (JSON i Documents), stores, RemoteCoach (SSE),
                     EventKit, lokala notiser
  DesignSystem/      färg-/avstånds-/rörelsetokens (DS.*), komponenter
  Core/              plattformsoberoende logik (SwiftPM-target "TeliaCore")
  Resources/         Assets.xcassets, SeedCatalog.json, innehålls-JSON
Tests/CoreTests/     71 enhetstester mot TeliaCore
backend/openai-proxy/ valfri engelsfils-proxy som håller API-nyckeln på server
tools/               gen_pbxproj.py, make_icon.py
docs/                PRIVACY.md, SIDESTORE.md
```

## Bygga & köra

**Krav:** macOS med Xcode 14+ (byggt för Xcode 16), iOS/iPadOS 16.0+.
Inga externa beroenden — Swift Charts är en systemramverk.

```bash
# 1. (endast vid behov) generera projekt + ikon — repo:t innehåller redan dessa
python3 tools/gen_pbxproj.py && python3 tools/make_icon.py

# 2. kärntester på valfri plattform (Linux funkar — inga Apple-ramverk behövs)
swift test

# 3. öppna i Xcode, välj scheme TeliaSalesAssistantPro, kör i simulator
open TeliaSalesAssistantPro.xcodeproj
```

### Bygga osignerad IPA (det är detta CI gör)

```bash
xcodebuild -project TeliaSalesAssistantPro.xcodeproj \
  -scheme TeliaSalesAssistantPro -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir Payload && cp -R dd/Build/Products/Release-iphoneos/TeliaSalesAssistantPro.app Payload/
zip -qry TeliaSalesAssistantPro-unsigned.ipa Payload
```

Se **docs/SIDESTORE.md** för installation på enheten med SideStore.

## CI (GitHub Actions)

`.github/workflows/ci.yml` körs på varje push/PR:

1. **Core unit tests (Linux)** — samma `swift test` som lokalt
2. **iOS build + tester (macOS, simulator)** — hela appen + 71 testerna
3. **Osignerad Release-IPA** laddas upp som artefakt (och bifogas releases för `v*`-taggar)

## Ärlighetsregler appen bygger på

- Priser/kampanjer/villkor uppfinns **aldrig** — allt från seed-katalogen
  (hämtad manuellt från telia.se 2026-10-18), din import eller din feed.
- Utgångna kampanjer visas aldrig som aktiva.
- Utvecklingsdashboarden visar bara manuellt inmatade siffror.
- Streaming visas bara när det verkligen streamar.
- Demo-svar märks tydligt i chatten.
- Ingen kund-PII, ingen analys, ingen spårning, alla filer lokalt i appens
  dokumentmapp + nyckel i Keychain. Se docs/PRIVACY.md.

## Prisdata

`Resources/SeedCatalog.json` (46 poster) verifierad mot telia.se 2026-10-18
(mobilabonnemang, bredband, TV, kontantkort, tillbehör) — käll-URL och
tidsstämpel per produkt. Uppdatera via:

- **Inställningar → Prisdata → Uppdatera nu** (JSON-feed via https)
- **Importera prislista** (JSON/CSV — formatet dokumenteras i
  `Core/Import/PriceImport.swift` och matchar appens export)

Import vs inbyggt: egenimport märks tydligt i källvyn. Medarbetarerbjudanden
som inte finns publikt får bara komma in via din egen import och visas med
den källan.

## Kampanjdata (1.1)

`Resources/CampaignSeed.json` (19 poster) verifierad mot offentliga sidor på
telia.se 2026-10-18 (erbjudanden, mobilabonnemang, bredband, TV, tillbehör).
Varje post har stabil ID, käll-URL, verifieringstid och — när Telia publicerar
det — slutdatum. Poster utan publicerat slutdatum märks "slutdatum overifierat".

Appen hämtar som standard projektets publicerade kampanj-JSON på GitHub vid
öppning (och på begäran). Misslyckas hämtningen behålls sparad data och en
tydlig varning visas — innehåll blir aldrig tyst inaktuellt. HTML-skrapning
av telia.se görs aldrig; Halebops inloggningskrävande personliga erbjudanden
ingår inte.

## Versionshistorik

- **1.1 (2) — Update 1.1 BETA**: Kampanj Center, egen bakgrund (gradienter,
  egen färg, egen bild — lokalt), AI-coach kampanjförankrad, skapare tillskriven
  ("Made by Kevork Khagadurian"), uppgraderingssäker inställningsläsning,
  107 kärntester (varav 35 nya).
- **1.0 (1)**: första leveransen.
