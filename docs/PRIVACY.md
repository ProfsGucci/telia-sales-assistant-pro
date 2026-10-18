# Integritetspolicy — Telia Sales Assistant Pro

Senast uppdaterad: 2026-10-18

Appen är byggd för personligt bruk av en enskild säljare. Den samlar inte in
data om dig och skickar ingenting någonstans om du inte själv konfigurerar en
AI-backend.

## Var data finns

| Data | Lagring |
|---|---|
| Konversationer med coachen | lokal JSON-fil i appens dokumentmapp |
| Kalender (pass, uppgifter) | lokal JSON-fil |
| Passloggar & mål | lokal JSON-fil |
| Träningshistorik (lektioner, quiz, flashcards) | lokal JSON-fil |
| Favoriter, manus, anteckningar, sparade svar | lokal JSON-fil |
| Inställningar (inkl. AI-server-URL) | lokal JSON-fil |
| API-nyckel/-token för AI-backend | iOS Keychain (`kSecAttrAccessibleAfterFirstUnlock`) |
| Priskatalog | lokal JSON-fil, seed bundlad i appen |

Ingen iCloud-synk. Ingen analys. Inga tredjeparts-SDK:er. Inga annonser.
Inga konton.

## När lämnar data enheten?

Endast om du konfigurerar en AI-backend (Inställningar → AI-backend):

- **Vad som skickas:** din senaste fråga, de 10 senaste meddelandena i
  konversationen samt produktdata som hämtas fram för att grunda svaret.
- **Vart:** den exakta server *du* angett (t.ex. din egen instans av
  `backend/openai-proxy`), som i sin tur vidarebefordrar till den
  AI-tjänst du konfigurerat.
- **Vad som aldrig skickas:** allt annat. Appen har inga fält för
  personnummer, betalningsuppgifter eller kundregister — skriv inte in sådana
  i chatten.

I demoläge skickas ingenting alls — svaren genereras lokalt och märks "demo".

## Behörigheter

- **Kalender (valfri):** används bara om du trycker "Lägg även i Apple
  Calendar". Appens egen kalender fungerar helt utan behörighet.
- **Notiser (valfritt):** lokala påminnelser 30 minuter före pass, samt (1.1)
  lokala påminnelser när en stjärnmärkt kampanjs verifierade slutdatum närmar
  sig. Inga push-notiser från server skickas någonsin.
- **Bilder (1.1):** appen begär **inte** behörighet till bildbiblioteket. Du
  väljer en enskild bild via systemets PhotosPicker; en nedskalad kopia sparas
  i appens egen mapp och lämnar aldrig enheten. Originalet lämnas orört.

## Kampanjdata (1.1)

Kampanj Center hämtar som standard en JSON-fil med verifierade kampanjer från
det här projektets publika GitHub-repo. Vid den hämtningen kontaktas
raw.githubusercontent.com — inga persondata skickas, och inga identifierare
lagras på någon server. Misslyckas hämtningen används sparad lokal data.

## Radera data

Inställningar → Data → **Radera all data…** tar bort alla lokala filer,
nollställer appens tillstånd och tar bort AI-nyckeln från Keychain.
Avinstallera appen tar givetvis bort allt. En importerad bakgrundsbild raderas
via Inställningar → Bakgrund → Återställ (eller med all övrig data ovan).

## Export

Inställningar → Data → **Exportera all data (JSON)** ger dig en fil med
allt innehåll — för backup eller flytt. Den innehåller **inte** API-nyckeln.
