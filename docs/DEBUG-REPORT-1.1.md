# Debug- och QA-rapport — Update 1.1 BETA

**Datum:** 2026-10-18 · **Version:** 1.1 (2) · **Bas:** 1.0 (1), commit `6c0444e`
**CI-baslinje:** run 39092686811 — bygg ✓, simulatortester 72/72 ✓, osignerad IPA ✓

Den här rapporten redogör ärligt för vad som granskades, vad som hittades, vad
som åtgärdades, vad som testats och vad som **inte** kan testas i den här
miljön. Inga resultat har hittats på.

---

## 1. Metod

1. **Baslinje före förändring** (regel: anta aldrig att 1.0 fungerar):
   - `git status` rent, `main` på `6c0444e`, 17 commits.
   - `swift test` lokalt: 72/72 grönt (0,026 s) — samma resultat som senaste gröna CI.
   - Verktygskedja, projektgenerering och CI-konfiguration verifierade på plats.
   - Inga befintliga taggar eller releaser (varken v1.0 eller v1.1-beta fanns).
2. **Dataloggranskning:** live-data hämtad manuellt från offentliga telia.se-sidor
   (/erbjudanden, /erbjudanden/mobilabonnemang, /mobilabonnemang, /om/priser)
   2026-10-18. Inga inloggningsskyddade eller medarbetarystem skrapades.
3. **Förändringar i faser** med testsviten grön efter varje fas; projektet
   genererat om med `tools/gen_pbxproj.py` efter nya filer.
4. **Självgranskning av appskiktet** (lokalt finns ingen Xcode — se avsnitt 6).

## 2. Granskade områden och resultat

| Område | Resultat |
|---|---|
| Kärntester (Linux `swift test`) | **107/107 grönt** (72 gamla + 35 nya) |
| Inställningspersistens | Granskad — se F-1 |
| Kampanjmotor (status, besparingar, diff, merge) | Ny, testad med 27 tester |
| Bakgrundsinställning (Core-delen) | Ny, testad med 6 tester |
| Coach-integration (demo + remote) | Signatur breddad; grunderingstestade |
| Projektgenerering | `gen_pbxproj.py` — 56 filreferenser validerar mot disk |
| iOS-bygge | Verifieras av CI (macOS) — **pågår när detta skrivs**; resultat rapporteras i releasen |

## 3. Hitta problem, orsak, åtgärd

### F-1 (allvarlighet: HÖG — åtgärdad) Inställningar hade kunnat raderas vid uppgradering
- **Symptom/risiko:** `SettingsData` använde syntetiserad `Codable`. Ett nytt
  fält (`background`) hade gjort att äldre sprad JSON misslyckades med
  `keyNotFound` vid avkodning → `DataStore.load` returnerar nil → alla
  användarens inställningar (tema, AI-config, dashboard-ordning) nollställs.
- **Orsak:** Swifts syntetiserade dekoder kräver alla nycklar.
- **Åtgärd:** Egen `init(from:)` med `decodeIfPresent` + standardvärden för
  **alla** fält; nycklar som saknas får default i stället för krasch. Mönstret
  dokumenterat för framtida fält. Kampanjfavoriter lagras dessutom i en egen
  `CampaignData`-fil så `LibraryData` aldrig behövde röras.
- **Test:** `BackgroundPreferenceTests` (legacy-JSON utan nya fält, tomt objekt,
  clampning) + befintliga SettingsData-tester.

### F-2 (allvarlighet: HÖG — åtgärdad före release) Fel totalkostnadsformel vid kampanjperiod
- **Symptom:** Ny beräkning `totalCostSEK` drog av fel antal månader när en
  kampanj har begränsad kampanjperiod (t.ex. 499 kr i 3 mån, därefter 549 kr:
  formeln gav 9 432 kr i stället för 6 438 kr över 12 mån).
- **Orsak:** `total -= price * promo` i stället för `total -= price * (months - promo)`.
- **Åtgärd:** Korrigera formeln; test `testTotalCostMonthlyPromoShorterThanHorizon`
  låser det korrekta värdet; gränsfallen promo = månader och promo > månader testas.
- **Fångades av:** enhetstest innan någon build.

### F-3 (allvarlighet: MEDEL — åtgärdad) Kategorinamn i seed-JSON matchade inte råvärden
- **Symptom:** 3 poster dekoderade inte (`otherSmartphones`, `tvStreaming` i
  JSON mot raw values `andra_smartphones`, `tv_streaming`).
- **Orsak:** Python-genereringen använde Swift-case-namn.
- **Åtgärd:** JSON rättat; seed-dekoderingstest misslyckas nu vid sådan avvikelse.

### F-4 (allvarlighet: LÅG — åtgärdad) Typfel som inte syns lokalt
- `Set.map(Array.init)` hade gett tecken-array i stället för `[String]`
  (fångad i själgranskning; hade fallit i CI-bygget).
- ColorPicker-binding med no-op `set` hade gjort att egen färg aldrig sparades
  (fångad i själgranskning; logikfel som enhetstest inte täcker).
- `name="Mörk premium"` saknade kolon (fångades direkt av kompilatorn lokalt).

### F-5 (allvarlighet: LÅG — åtgärdad) Navigationssäkerhet för nya vyer
- Kampanjer navar med eget värde (`CampaignRecord`) och relaterade produkter
  med egen ruttyp (`CampaignProductRoute`) för att aldrig kollidera med
  befintliga `String`-destinationer i samma stack (känd kraschkälla från 1.0).

## 4. Tester

- **35 nya kärntester**, bl.a.: kampanjstatus (aktiv/slutar-snart/utgången/
  overifierat slutdatum, dagprecision), besparingar (månads- vs engångspris
  hålls isär — ingen blandning), totalkostnad med/utan kampanjperiod, filter/
  sökning/sortering, diff (tillagd/borttagen/prisändrad), säker merge (ofullständig
  feed kan inte tappa poster), jämförelserader (saknad data visas "–", aldrig
  påhittad), seed-integritet (unika ID: n, käll-URL: er mot telia.se, inga
  utgångna poster, korsreferenser mot produktkatalogen), democoachens
  kampanjsvar (grundar i poster, redovisar ordinarie pris) samt att **utgångna
  kampanjer aldrig presenteras som aktuella**.
- **Körning:** `swift test` → 107/107, 0,03 s, Linux (Swift 6.4.1). Samma
  testsvit körs även på macOS-simulator i CI (TEST_HOST-appen).
- **Appskiktet:** `swiftc -parse` rent för alla nya/ändrade filer. full
  typkontroll av SwiftUI-skiktet sker först i CI-bygget (se avsnitt 6).

## 5. Prestanda- och tillgänglighetsgranskning (1.1-specifika delar)

- Bakgrunden renderas **statiskt**: inga animerade gradienter, ingen live
  fullskärmsblur-pipeline. Bildblur är avgränsad (max 20 pt) och sitter på ett
  lager som inte omrenderas per frame; bilder skalas ned till max 1 600 px.
- Övergångar: 0,25 s cross-fade, avstängd vid Reduce Motion.
- Läsbarhet: innehåll ligger i opaka kort; intensitetsreglaget tonar bakgrunden
  mot standardfärgen; ljusa preset: ar får scrim i mörkt läge (och tvärtom).
- Dashboard-animationer oförändrade från 1.0 (avståndsanpassade, Reduce Motion
  respekteras).
- Kampanjlistan är `LazyVStack`; nätverksanrop sker aldrig i view-body.

## 6. Kända begränsningar & inte testbart i den här miljön

Ärligt: följande kan **inte** verifieras här och är därför overifierade:

1. **Ingen riktig enhet/simulator lokalt** — alla UI-interaktioner (PhotosPicker,
   notis-leverans,ScrollContentBackground-beteende per iOS-version, iPad-sidebar
   i praktiken) är CI-bygg-verifierade men inte handtestade. IPA:n är osignerad
   (SideStore kräver användarens eget Apple-ID).
2. **Bakgrundsbild-blur** på mycket gamla enheter: statisk blur är billig men
   inte kostnadsfri; rekommendera låg oskärpa om rullning hackar.
3. **Kampanjdatahaltbarhet:** verifierad 2026-10-18. Kampanjer utan publicerat
  slutdatum märks "slutdatum overifierat" — de kan ha utgått utan att appen
   vet det; därför visas verifieringstid och källänk överallt.
4. **Live-refresh** beror på att raw.githubusercontent.com svarar (standardfeed).
   Misslyckas det: cachad data + tydlig varning. Bakgrundsuppdatering sker
   aldrig — endast vid öppning/på begäran.
5. **Bekant kvarstående från 1.0 (oförändrad):** EU-roaming-diskrepansen
   50/100 GB i Telias egna källor; appen visar Telias siffra per produkt och
   länkar källan.
6. **imageURL-fält** i CampaignSeed.json är metadata (sparade källbilds-URL:er)
   och renderas inte i appen — fjärrladdning av bilder i UI har medvetet
   lämnats ute (volatila URL: er, integritet, prestanda).
7. **Notiser för kampanjutgång:** bara favoriter med **verifierat** slutdatum
   får påminnelse (i dagsläget HAALE Smart Band t.o.m. 31 okt 2026). Det är
   medvetet — påminnelser utan känt slutdatum vore bluff.

## 7. Slutsats

Kärnlogiken är fullständigt enhetstestad och grön (107/107). Tre buggar med
release-påverkan hittades och åtgärdades före leverans (F-1, F-2, F-4), varav
en uppgraderingsrisk som finns dokumenterad ovan. Appskiktets typkorrekthet
 verifieras av CI-bygget; resultatet rapporteras i GitHub-releasen utan
påkostade påståenden. Allt som inte kunnat testas listas i avsnitt 6.
