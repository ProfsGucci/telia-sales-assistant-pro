# Kalenderintegration — konfiguration (Google & Microsoft)

Appen har **riktiga** OAuth-flöden och API-klienter för Google Calendar och
Microsoft Outlook/Microsoft 365. Båda kräver dock att appägaren registrerar
en egen applikation hos respektive leverantör och anger dess **client ID** i
appens Inställningar → Kalendrar. Utan det visas leverantören som
”Kräver konfiguration” och går inte att ansluta — medvetet, så att inget
låtsas fungera som inte gör det.

Apple Kalender kräver ingen förkonfiguration: den använder systemets
behörighet (EventKit) och fungerar direkt.

---

## Google Calendar

### 1. Skapa ett projekt och aktivera API:et

1. Gå till [Google Cloud Console](https://console.cloud.google.com/).
2. Skapa (eller välj) ett projekt.
3. **APIs & Services → Library** → sök **Google Calendar API** → **Enable**.

### 2. Konfigurera OAuth-consent-skärmen

1. **APIs & Services → OAuth consent screen**.
2. User Type: **External** (eller Internal om du har Google Workspace).
3. Lägg till scopet `https://www.googleapis.com/auth/calendar.readonly`.
4. Lägg till din egen e-post som testanvändare (om appen är i Testing-läge).

### 3. Skapa OAuth-klienten

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. Application type: **iOS**.
3. Bundle ID: `se.sthlm.teliacoachpro`
4. Efter skapandet: under **iOS URL scheme** lägg till
   `se.sthlm.teliacoachpro.oauth` (detta är appens callback-schema).
5. Kopiera **Client ID** (slutar på `.apps.googleusercontent.com`).

### 4. I appen

1. Inställningar → Kalendrar → Google Calendar.
2. Klistra in client-ID:t i fältet.
3. Tryck **Logga in och anslut** → Googles egna inloggningssidor öppnas i
   systemwebbläsaren (ASWebAuthenticationSession) → godkänn.
4. Välj vilka kalendrar som ska visas i appen.

**Teknik:** OAuth 2.0 Authorization Code flow med PKCE (S256). Inga client
secrets används eller behövs (publik native-klient). Token lagras i
enhetens Keychain (`se.sthlm.teliacoachpro.calendar`). Behörighet som
efterfrågas: `calendar.readonly` — appen kan aldrig ändra i din Google-kalender.

---

## Outlook / Microsoft 365

### 1. Registrera appen i Azure

1. Gå till [Microsoft Entra admin center](https://entra.microsoft.com/)
   (eller Azure Portal → App registrations).
2. **New registration**.
   - Name: t.ex. `Telia Sales Assistant Pro`
   - Supported account types: valfritt (t.ex. ”Accounts in any
     organizational directory and personal Microsoft accounts”).
   - Redirect URI: **Public client/native (mobile & desktop)** →
     `se.sthlm.teliacoachpro.oauth:/oauth`
3. Kopiera **Application (client) ID**.

### 2. Behörigheter

1. Under **API permissions → Add a permission → Microsoft Graph**:
   - **Delegated** → `Calendars.Read`
   - **Delegated** → `offline_access` (för refresh-token)
2. Användare godkänner själv vid inloggning (inget admin-consent behövs för
   dessa).

### 3. I appen

1. Inställningar → Kalendrar → Outlook / Microsoft 365.
2. Klistra in client-ID:t.
3. **Logga in och anslut** → Microsofts inloggningssida (v2-endpoint,
   PKCE) → godkänn.
4. Välj kalendrar.

**Teknik:** Microsoft identity platform v2 + Microsoft Graph
(`/me/calendars`, `/me/calendars/{id}/calendarview`), delegated
`Calendars.Read` + `offline_access`. Token i Keychain. Skrivskyddat.

---

## Synkroniseringsmodell (ärlig beskrivning)

- Hämtning sker **periodiskt och manuellt**: när appen blir aktiv (tidigast
  var 15:e minut) och via uppdateringsknappen. Det är INTE realtid.
- Fönstret som hämtas: en månad bakåt till tre månader framåt.
- Importerade händelser är **skrivskyddade** i appen. Original finns kvar
  hos leverantören; ändringar göras där och syns vid nästa synk.
- Duplicering förhindras genom att händelser identifieras med
  (leverantör, kalender-ID, händelse-ID): redigerade händelser uppdateras
  på plats, borttagna försvinner vid nästa synk.
- Återkommande händelser expanderas av respektive API (Google
  `singleEvents=true`, Graph `calendarView`, EventKit occurrence-expansion)
  och tidszoner hanteras vid parsningen (RFC 3339 + händelsens tidszon).
- Google/Outlook-token kan upphöra (återkallat medgivande, lösenordsbyte).
  Appen visar då felet och erbjuder att koppla upp igen.
- Kalenderinnehåll lämnar aldrig telefonen i onödan: appen pratar direkt
  med leverantören, ingen mellanserver.

## Sekretess

- Token lagras i Keychain, aldrig i filer eller inställningar.
- Client-ID:n är användaregenskaper (inställningsfält), inte inbakade i
  app-binären; inga hemligheter finns i källkoden.
- Kalenderhändelser skickas aldrig till AI-coachen eller någon tredje part.
