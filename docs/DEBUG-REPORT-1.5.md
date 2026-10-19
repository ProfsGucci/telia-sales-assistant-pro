# Debug-/QA-rapport — Update 1.5 BETA

**Version:** 1.5 (6) · **Datum:** 2026-10-19 · **Ansvarig arbetsgång:** full
repo-granskning före ändringar, Core-tester efter varje Core-ändring, ändringar
inom befintliga arkitektur-/designmönster.

---

## 1. Vad som granskades innan ändringarna

- Arbetskopia ren mot `main` @ `c2d6f08` (Update 1.4:s dokumentationscommit).
- Swift 6.4.1-toolchain (Linux) ominstallerad; baslinje **151/151** tester
  gröna innan första 1.5-ändringen.
- Integrationspunkter auditade i kod: DashboardView-kortregister +
  `orderedCards` (nytt kort måste appendas i slutet för befintliga
  användare), ChatView-draft (`inputBar`/`send`), AppState-seedmönstret
  (`productSearchSeed`, TeliaApp.swift:99), CampaignDetail-jämförknappar,
  ProductDetail "Jämför", CampaignStore `activeCampaigns` (relevanssort,
  utgående först, `endDate nil` = opublicerat), SettingsView
  dataSection/reminderSection, FollowUpStore `didSet`-persistens.
- Begränsning (känd sedan 1.4): Linux `swift test` kompilerar **bara**
  SwiftPM-paketet (Core). App-lager kompileras av CI:s xcodebuild. Därför:
  alla nya app-filer tillagda i `tools/gen_pbxproj.py`-flödet (omgenererad
  pbxproj) OCH `swiftc -parse`-syntaxkontroll kördes lokalt på samtliga
  ändrade app-filer.

## 2. Ändringar (1.5)

### Core (testat på Linux, ingår i de 166 testerna)
- `Core/Progress/SalesGoalModels.swift` — tempomotor: `SalesGoalPace`
  (ahead/onTrack/behind/notApplicable), `snapshot.expectedProgress`,
  förfluten tid per dagsbas (exklusive idag), ±5 %-band, tidig-start- och
  framtida-start-fall, `isWorkingDay`-hjälp.
- `Core/Coaching/DailyBrief.swift` (NY) — daglig brief: källmärkta items
  (Uppmätt/Inmatat/Beräknat/Verifierat), EN regelbaserad rekommendation
  (prioritet: försenat → idag → efter tempo → kampanj ≤3 d → inga mål →
  default). Namn får förekomma, personnummer aldrig.
- `Core/FollowUp/FollowUpModels.swift` — integritetssäker
  påminnelsetext ("Kunduppföljning" / "Du har N kunduppföljningar idag.").
  **Bugg hittad och fixad under QA:** `reminderBody(count: 0)` returnerade
  "Du har **en** kunduppföljning" — oriktig svensk wording för noll;
  nu "Du har inga kunduppföljningar idag." (Oåtkomlig via schemaläggaren,
  men fel i API:t.)

### App-lager (komileras av CI; syntaxkontrollerad lokalt)
- `Features/Home/TodayCard.swift` (NY) — Dagens prioriteringar: rader för
  försenade/dagens uppföljningar (→ Kolla senare-vyn), daglig target +
  tempochip, dagens händelser (Schema + importerade kalendrar), kampanjer
  ≤7 dagar kvar, EN rekommendation, knappar "Dagens brief" och
  "Kolla senare". `DailyBriefSheet` — List med käll-etiketter +
  förklarande footer (verklig vs inmatad vs beräknad data).
- `Features/Home/DashboardView.swift` — `.today`-kort först i default-
  ordningen (nya användare); befintliga användares sparade ordning får
  kortet tillagt i slutet (inget tvingas om).
- `Features/Progress/SalesGoalsView.swift` — tempochip (före/i tempo/efter)
  med förväntad progresprocent i "efter"-meddelandet; dubbeltrycksskydd
  (`isSaving`) + `SalesGoalEngine.isValid` innan upsert; misslyckad
  validering återaktiverar spara-knappen.
- `Features/FollowUp/FollowUpViews.swift` — datumfilter (alla/idag/7/30/
  försenade), röd led-list på försenade rader, dubbeltrycksskydd i
  snabblägg; sparade uppföljningar omschemalägger påminnelser.
- `Services/FollowUpNotifications.swift` (NY) — lokala påminnelser:
  per framtida förfallodag kl 09:00, innehåll = antal (aldrig namn/
  personnummer), idempotent full omschemaläggning (aldrig dubbletter),
  fullständig behörighetshantering via UNUserNotificationCenter.
- `Services/FollowUpStore.swift` — `didSet` sparar OCH håller påminnelser
  synkade (no-op när avstängda).
- `Services/Persistence.swift` — `SettingsData.followUpRemindersEnabled`
  (opt-in, tolerant dekodning).
- `Features/Calendar/CalendarView.swift` — dagsvyn visar förfallna
  uppföljningar (ENDAST visning: FollowUpStore förblir enda källa, inga
  kalenderposter skapas → inga dubbletter).
- `Features/Coach/ChatView.swift` + `App/TeliaApp.swift` —
  `AppState.coachSeed`: produkt-/kampanjknappar ("Fråga coachen" /
  "Öva med AI-coachen") förifyller coachens utkast med verifierad
  kontext (pris, ordinarie pris, bindningstid med i frågan). **Inget
  skickas automatiskt** — användaren trycker själv på skicka.
- `Features/Products/ProductDetailView.swift`,
  `Features/Campaign/CampaignDetailViews.swift` — knapparna ovan.
- `Features/Settings/SettingsView.swift` — tredje notistoggle (uppföljnings-
  påminnelser, opt-in, behörighet efterfrågas vid påslagning, avslag återspeglas
  ärligt i toggle-läget), "Radera kunduppföljningar (N)" med
  bekräftelsedialog.
- `tools/gen_pbxproj.py` + omgenererad pbxproj — version 1.5 (6), nya filer
  med targets (TeliaCore 19, app 39, tester 13 filer).

### CI
- `.github/workflows/visual-qa.yml` (NY) — bygger appen, bootar
  iPhone-simulator, installerar + startar, skärmdumpar dashboard i **ljust
  och mörkt** läge, verifierar att PNG:erna finns och inte är tomma,
  laddar upp dem som artifact och bifogar dem i v*-releaser. Detta är
  verktyget för den visuella verifiering specen kräver (se §5).

## 3. Tester som faktiskt kördes

| Körning | Resultat |
|---|---|
| Baslinje `swift test` (före 1.5-ändringar) | **151/151 gröna** |
| Efter Core-ändringar (pace, DailyBrief, reminder) | 151/151 gröna |
| Slutlig `swift test` med nya tester | **166/166 gröna** |
| `swiftc -parse` på alla ändrade/nya app-filer | 0 syntaxfel |
| Ny testfil `Tests/CoreTests/Update15Tests.swift` | 15 tester: pace ×5 (före/i/efter band, ej startad/klar, passdagar), DailyBrief ×8 (tom/saknas, mål tak 3, uppföljningar utan pnr, händelser, kampanjer, rekommendationsprioritet ×3), påminnelsetext ×2 |

## 4. Buggar hittade under arbetet

1. `reminderBody(count: 0)` → "en kunduppföljning" (fixad, se ovan).
2. Spara-knappens dubbeltrycksskydd fastnade i "sparar"-läge om validering
   misslyckades (tre guard-grenar återställde inte `isSaving`) — fixad med
   `isSaving = false` i varje felgren; samma mönster i FollowUp-quick-add.
3. (Processfel, fångat direkt): test-fixtur förväntade sig "on track" men
   matematiken gav "efter" (17/31 dagar förflutna → förväntad ≈10,97, inte
   10) — fixture korrigerad, ingen produktionsändring.

## 5. Verifiering av glossy (spec-krav: "bygg + kör i simulator där möjligt")

- 1.4:s glans (`DesignSystem/Gloss.swift`, DS 2.3) är oförändrad i 1.5 —
  inga rotorsaks-regressioner har introducerats (inga nya lager ovanpå
  glaskorten; TodayCard använder befintliga SectionCard/Gloss-komponenter).
- **Ny Visual QA-workflow** fångar dashboard i ljust + mörkt på varje push
  och bifogar bilderna i releasen. Skärmdumparna för v1.5-beta har
  granskats (dashboard med kortvy, båda lägena) — resultat: glansen är
  synlig (ljusband, kant, sweep) i båda lägena.
- Ärlighetsgräns: CI-simulatorn fångar **dashboarden efter start** —
  djupare vyer (kampanjdetalj, produktkort med sweep på markerade kort)
  verifieras inte automatiskt; det kräver manuell granskning i simulator
  på egen dator. Detta dokumenteras som kvarvarande begränsning.

## 6. Kvarvarande begränsningar (kända och medvetna)

- **Simulator-skärmdumpar täcker bara startvyn** (dashboard) — se §5.
- Kalender-import förblir skrivskyddad (oförändrad från 1.4; ingen
  tvåvägssync påstås).
- Google/Outlook-OAuth kräver fortfarande extern konfiguration
  (docs/CALENDAR-SETUP.md) — oförändrat.
- Påminnelser är lokala och schemaläggs när appen används (ingen
  server-push påstås); iOS kan skjuta fram leverans.
- AI-coachen kräver fortfarande konfigurerad backend-URL; demoläge märks
  tydligt. Coach-seed skickar aldrig något automatiskt och innehåller
  aldrig personnummer.
- Personnummer lagras lokalt på enheten (som sedan 1.4). Om Telia-policy
  förbjuder lokal lagring: använd inte Kolla senare-funktionen, eller
  radera data via Inställningar → Radera kunduppföljningar. Appen varnar
  i Settings-footern om den lokala lagringen.

## 7. Checklista (acceptanskriterier)

- [x] Dashboard = kommandocentral med Dagens prioriteringar (verklig data)
- [x] Dagens brief ≤1 tryck från dashboard, källmärkt, "saknas" när saknas
- [x] Målmotor: konfigurerbara kategorier, required/day, tempo, kanter,
      helhetsavrundning — 166 tester
- [x] Uppföljningar: exakt 4 fält, filter, brådskande, dubbeltrycksskydd,
      påminnelser (opt-in, integritetssäker text)
- [x] Kalender: dagsvy visar uppföljningar utan dubbletter
- [x] Coachen öppningsbar från produkt/kampanj med förifylld fråga
- [x] Kampanjer: oförändrade verifieringsregler (1.4), utgår i brief endast
      verifierade slutdatum
- [x] Visual QA-workflow: skärmdumpar ljust + mörkt i varje build
- [x] Inställningar: notissektion + radera kunduppföljningar
- [x] Version 1.5 (6), README + release notes
- [x] 166/166 kärntester gröna (dokumenterade ovan)
- [x] IPA byggs av CI och verifieras innan release-påstående
