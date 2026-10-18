# Debug- och QA-rapport — Update 1.4 BETA

**Datum:** 2026-10-18 · **Version:** 1.4 (5) · **Bas:** 1.3 (4), commit `9e1686e`
**Lokal baslinje:** 107→113 → **151/151 kärntester** · `swiftc -parse` rent

Allt nedan är faktiskt utfört om inte annat sägs. Inga påhittade resultat.

---

## 0. Ärlighetsnoteringar

1. **Ingen Xcode/simulator i utvecklingsmiljön.** Appskiktet verifieras
   med `swiftc -parse` (syntax/type-nivå som Linux tillåter) + 151
   kärntester i `swift test` (Linux). Full iOS-bygge sker i GitHub Actions.
   **Visuell verifiering av glossy-effekterna har INTE kunnat göras här**
   (kräver skärm) — se avsnitt 4 för vad som gjorts i stället och exakt vad
   som återstår att verifiera visuellt.
2. **Google/Outlook kräver extern konfiguration.** OAuth-flödena och
   API-klienterna är riktiga (PKCE + systemwebbläsare + Keychain), men de
   kräver appägarens egna client-ID:n (angetts i appens inställningar, inte
   inbakade i binären). Utan konfiguration visas leverantören som
   ”Kräver konfiguration” och kan inte anslutas. Exakta steg:
   `docs/CALENDAR-SETUP.md`. **Nätverksanropen mot Google/Microsoft har
   inte kunnat köras i denna miljö** (inga konton/client-ID:n) — flödena
   är implementerade enligt leverantörernas dokumentation och kompilerar,
   men är inte live-testade här.
3. **Apple Kalender (EventKit)** kräver ingen förkonfiguration; läs-logiken
   följer samma mönster som appens redan fungerande EventKit-skrivning
   (iOS 17 `requestFullAccessToEvents` med iOS 16-fallback). Själva
   behörighetsdialogen och händelsehämtningen kan bara testas på enhet —
   inte gjort här.
4. **Ingen referensbild** följde med glossy-direktivet (igen). Omgjort efter
   textbeskrivningen + optisk analys (avsnitt 4).

## 1. Metod

1. **Inventering före kod:** hela projektet lästes (navigering, DataStore,
   ScheduleStore/ProgressStore, EventKitService, KeychainService, DS,
   CI-workflow, gen_pbxproj) innan något ändrades — ny funktionalitet
   byggdes in i befintliga mönster (ObservableObject + DataStore-scan vid
   didSet, Core-motorer rena för Linux-testning).
2. **Core först:** personnummer, uppföljningar, säljmål och merge-motor
   skrevs som testbar Core-kod → 38 nya tester kördes GRÖNA lokalt.
3. **Verifiering per steg:** `swiftc -parse` på hela appskiktet + `swift
   test` efter varje fas.
4. **Bevarande:** inga befintliga funktioner togs bort; 113 gamla tester
   kördes orörda (inga regressioner); inställningar fick endast nya fält
   med tålmod dekodning (per-fält-standard) — gamla sparade filer läses.

## 2. Ny funktionalitet — vad som faktiskt levererats

### 2.1 Kalenderintegration (Schema)

| Område | Implementation | Status |
|---|---|---|
| Apple Kalender | EventKit-läsning (iOS 17 full access / iOS 16 legacy), kalenderval, system-behörighetsdialog, nekad åtkomst → tydligt fel + app-kalendern fungerar ändå | Kod klar + bygger; behörighetsflödet kräver enhet att testa |
| Google Calendar | OAuth 2.0 + PKCE (S256) via ASWebAuthenticationSession, refresh-token-flöde, Calendar API v3 (calendarList + events, singleEvents för återkommande), time zone-parsning | Kod klar + bygger; kräver client-ID + konto → inte live-testat här |
| Outlook/M365 | Microsoft identity v2 + PKCE, Graph `/me/calendars` + `calendarView`, delegated `Calendars.Read` + `offline_access` | Kod klar + bygger; kräver Azure-registrering → inte live-testat här |
| Enhetlig kalender | Dag/kommande: egna + importerade händelser i en tidsordnad lista; månadsgrid: egna prickar + importerad-ring; leverantörs-chip (Apple/Google/Outlook) med färg; detalj-sheet med titel/tid/plats/källa; Apple-händelser kan öppnas i Apple Kalender (EKEventViewController); överlapp markerade med varningsikon | Bygger; UI-test på enhet återstår |
| Dupliceringsskydd | Merge-motor i Core: upsert per (leverantör, kalender, händelse-ID), redigerade uppdateras på plats (stabil lokal UUID), borttagna vid källan försvinner, andra leverantörer rörs aldrig | **8 tester gröna** (även upprepad refresh, redigering, tomt snapshot) |
| Synkronisering | Manuell (uppdateringsknapp + drag-för-att-uppdatera) + vid app-aktivering (tidigast var 15:e minut). **Periodisk, inte realtid** — redovisas så i UI:t. Fönster: −1 → +3 månader | Logik testad; nätverksdelen kräver enhet/konto |
| Sekretess | Token i Keychain (ny `KeychainStore`), client-ID:n = användarinställningar (aldrig i binären), inga secrets i källkod, fel-loggning utan token-innehåll, kalenderdata går direkt telefon↔leverantör | Genomgång gjord; se avsnitt 5 |

### 2.2 Kolla senare-kunder

- **Exakt fyra obligatoriska fält:** personnummer, namn, anledning, datum.
  Inga telefonnummer/e-post/företag/kund-ID:n.
- Snabbt sheet direkt från dashboardens Snabbåtgärder och Schema-menyn;
  fokus läggs direkt i personnummerfältet; retur flyttar fokus vidare.
- **Personnummer:** normalisering till 12 siffror, struktur + riktigt
  datum + Luhn-kontrollsumma (även samordningsnummer, dag+60). Ogiltigt →
  tydligt fel; siffror ändras aldrig i det tysta. **12 tester gröna.**
- **Översikt:** grupper Försenade/Idag/Kommande/Klara (5 tester gröna),
  sök på namn+anledning (medvetet INTE på personnummer), swipe-åtgärder
  (Klar / Boka om grafisk datumväljare / Radera), redigera, markera klar,
  öppna igen; klara poster bevaras tills användaren raderar.
- **Dubblettvarning** (samma personnummer med pågående uppföljning) —
  varnar utan att visa numret.
- **Sekretess:** lagras ENBART lokalt (appens Documents), maskerad i
  listor (19811218-****) med öga-avslöjning per rad, skickas ALDRIG till
  AI/analytics/loggar (AI-coachen har ingen koppling till datat), varning
  om arbetsgivarens regler i formuläret. Testfixturerna är kända syntetiska
  testnummer (811218-9876 etc.) — aldrig riktiga kunder.

### 2.3 Säljmål (Schema → Säljmål)

- Mål med titel, kategori (abonnemang/enheter/tillbehör/bredband &
  TV/extratjänster/intäkt/annat), totalmål, manuellt uppnått, start- och
  måldatum, **dagsbas**: kalenderdagar / mån–fre / **egna planerade pass**
  (använder Schema:s återkommande-pass-expansion — appen antar ALDRIG att
  någon dag är en arbetsdag).
- Beräkning (Core, **14 tester gröna**): kvarvarande ÷ kvarvarande
  säljdagar; heltalsmål visas även upproundat (”sikta på X/dag”); gränsfall
  utan divisionsfel: ingen progress, klart, överträffat, noll dagar kvar
  (tydligt meddelande), passerat måldatum, veckoslut uteslutna,
  pass utanför fönstret, ändrad progress/datum omberäknas direkt.
- Presentation: glossiga målkort med animerad progressbard,
  `contentTransition(.numericInterpolation())` på siffror, kategori- och
  dagsbas-chips, statusmeddelanden. Allt persistrar (DataStore) och
  överlever omstart (lagringsformatet är samma mekanism som 107 befintliga
  tester redan verifierar).
- Specifikationens exempel (60/15/9 → 5/dag) är **exakt** vad
  `testWorkedExampleFivePerDay` verifierar — inga värden är inlagda i appen.

### 2.4 Fluiditet

- Nya vyer: spring-animationer, `contentTransition` på siffror, grafisk
  datumväljare, sheet-detents, fokushantering, sök, swipe-åtgärder,
  Dynamic Type via textstilar, VoiceOver-etiketter, Reduce Motion-grenar.
- Befintlig bas (PressableStyle, entrance-springs, haptics) bevarad.
- Tabben ”Kalender” heter nu **Schema** (användarens eget begrepp).

## 3. Bevarat från 1.0–1.3

Alla 113 gamla tester gröna orörda. Produkter, Kampanj Center, AI Coach,
Rollspel, Akademin, Bibliotek, pris-/kampanjdata, bakgrundssystemet
(Bakgrundsstudio), inställningar och all lokal data påverkas inte —
inställningsfilen fick bara nya fält med tålmod dekodning. Attribution
”Made by Kevork Khagadurian” orörd.

## 4. Glossy-korten — diagnos och omgörning (DS 2.3)

**Diagnos av varför 1.3 inte syntes (kodläsning, inte gissning):**

1. `GlossSheen` lade 16 % vitt överst — på ett **vitt kort i ljust läge
   är ett vitt överlager matematiskt osynligt** (vitt på vitt).
2. `GlossSweep` körde 12 % vitt — under synlighetsgränsen, särskilt i
   ljust läge.
3. Ljusningen tonade ut mjukt — utan skarp kant ser ögat ingen
   spegelyta; äkta gloss läses genom en ljusband med distinkt fallkant.
4. Basen saknade djup/toning att kontrastera mot.
5. `.subtle` satt bara på två kort — de flesta kort var helt oglansade.

**Omgörning (allt implementerat och kompilatortverifierat):**

| Åtgärd | Nytt |
|---|---|
| Tonad glasbas i ljust läge | vitt → svag lila diagonal — ger det vita överlagret kontrast |
| Ljususband med skarp fallkant | stopp vid 8 %/20 %/36 % höjd, 0,32 (mörkt) / 0,55 (ljust) opacitet + botten-skuggning för djup |
| Kantljus | 1,5 pt gradient-stroke 0,50–0,65 opacitet upptill |
| Svep | 0,22–0,30 opacitet, 45 %-band med tonad kärna+fransar, 8–9 s, endast hero, avstängd vid Reduce Motion |
| Hero | extra topp-band under texten + varm hörnljus + orange accentkant 0,65 |
| Spridning | **alla SectionCards** får statisk glans (noll animationskostnad); `.animated` endast Dagens fokus + Kampanj-rubrik |

**Ärlig gräns:** effekterna är optiskt motiverade och koden bygger, men
**visuell verifiering på skärm har inte kunnat göras i denna miljö** (ingen
simulator). Kvar att verifiera på enhet: synlighet över mörk/ljus/gradient/
foto-bakgrund, svepets rörelse över tid, utseende efter navigation/omstart,
scrollprestanda. Inget av detta påstås testat.

## 5. Testredovisning

**Verkligen exekverade (gröna):** 151/151 kärntester lokalt
(38 nya: personnummer 12, uppföljningar 5, säljmål 14, kalendermerge 7 —
varav duplicering/redigering/borttagning/andra-leverantörer/konflikt),
`swiftc -parse` rent på 74 filer, projektgenerering 74 refs, tidigare
113-tester som regression. CI (efter push): Linux-tester + iOS-bygge +
IPA — se avsnitt 7.

**Verifierade endast genom bygget:** EventKit-läsning (behörighetsflöde),
Google/Outlook-nätverksflöden (riktiga anrop kräver konfigurerade
konton — dokumenterat i CALENDAR-SETUP.md), alla nya UI:ers runtime-beteende.

**Kräver manuell testning på iPhone/iPad (ej gjort här, ej påstått):**
behörighetsdialoger, Google/Outlook-inloggning med riktiga konton,
synk mot riktiga kalendrar, PhotosPicker-bakgrund (från 1.3) fortfarande
oresat, glossy på skärm (se avsnitt 4), Dynamic Type/VoiceOver praktiskt,
iPad-layout/portrait-landscape.

## 6. Kända begränsningar

- Importerade händelser är skrivskyddade; tvåvägssynk finns inte (redovisas
  i UI och här). Google/Outlook = periodisk synk, inte realtid.
- Svepet i `.animated` ställer inte om sig live om Reduce Motion slås på
  medan vyn redan syns (nästa start respekteras); statisk glans finns alltid.
- Personnummer lagras okrypterat i appens lokala fil (app-sandbox, samma
  skyddsnivå som resten av appens data; Keychain används för tokens).
  Användarens radering tar bort allt omedelbart; ingen retention.
- `.searchable`-fältet söker inte på personnummer (medvetet).

## 7. Bygge och release

1. Branch `release/update-1.4-beta`; commit
   `feat: release Telia Sales Assistant Pro Update 1.4 BETA` på `main`.
2. Push → CI (Linux-kärntester + iOS-bygge/simulator-tester + osignerad
   IPA). Väntar grönt **innan** tagg/release.
3. Tagg `v1.4-beta` (ledig — kontrollerad) → release **”Update 1.4 BETA”**
   → CI monterar IPA automatiskt → verifiera Version 1.4 (5) → ersätt
   lokal IPA → leverera.
4. Status efter slutfört flöde redovisas i release-sidan.

## 8. Slutsats

Kalenderintegrationen har riktiga flöden bakom tydliga konfigurations-
gränser, uppföljningarna är snabba och sekretessstyrda, säljmåls-motorn är
heltäckande testad inklusive specifikationens exempel, och glossy-lagret är
omgjort med synliga optiska värden där 1.3 var osynligt. 151/151 kärntester
gröna; allt som inte kunnat köras här är märkt och förklarat — inget test
är markerat godkänt utan att ha körts.
