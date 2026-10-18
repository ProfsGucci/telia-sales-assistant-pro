# Installera med SideStore

SideStore låter dig installera egna appar på iPhone/iPad utan App Store och
utan Mac i vardagen. Appen bygger för iOS/iPadOS **16.0+**; SideStore kräver
**iOS/iPadOS 15.0+** — kraven går ihop.

## Fakta om SideStore (verifierat 2026-10-18)

- Installationen av SideStore själv kräver en dator **en gång** (AltServer/
  SideServer kopplad via USB eller trådlöst), ett Apple-konto och Wi-Fi.
- Med ett **gratis Apple-ID** signerar SideStore på enheten: högst **3 aktiva
  egna appar** i taget, och signaturerna håller **7 dagar**. SideStore
  förnyar dem i bakgrunden via en liten VPN-profil när appen körs regelbundet.
- Med betalt Apple Developer-konto (ca 99 USD/år) blir apparna giltiga i
  ett år och gränsen försvinner.
- Osignerade IPA:er är precis det SideStore vill ha — det signerar dem själv
  med ditt Apple-ID på enheten.

## Steg

1. **Skaffa en IPA.** Antingen:
   - ladda ner artefakten `TeliaSalesAssistantPro-unsigned` från repo:ts
     GitHub Actions-körning (innehåller `TeliaSalesAssistantPro-unsigned.ipa`),
     eller
   - bygg själv enligt README ("Bygga osignerad IPA").
2. **Installera via SideStore.** Öppna SideStore → fliken Apps → + → välj
   IPA-filen (t.ex. via Fil-appen) → Installera. Godkänn eventuell
   "Osignerad app"-varning.
3. **Starta appen.** iOS kan fråga om du litar på utvecklarkontot — det är
   normalt vid första installationen med eget Apple-ID.

## Vanliga frågor

**"Appen slutar fungera efter en vecka."**
Signaturen från gratis Apple-ID upphör efter 7 dagar. Öppna SideStore och
tryck Uppdatera/Refresh på appen (kräver Wi-Fi).

**"Kan jag installera fler än 3 egna appar?"**
Med gratis Apple-ID: nej — avinstallera en först. Med betalt konto: ja.

**"Behöver jag en server igång för AI-coachen?"**
Nej. Utan server kör appen i demoläge (tydligt märkt). Vill du koppla en
riktig modell: sätt upp `backend/openai-proxy` enligt dess README och fyll i
URL + token i Inställningar → AI-backend.

**"Raderas min data vid uppdatering?"**
Nej — ny version installeras ovanpå samma bundle-ID (`se.sthlm.teliacoachpro`)
och datafiler ligger kvar. Avinstallation däremot raderar allt.

---

*Källor: sidestore.io och SideStore-dokumentation, besökta 2026-10-18.*
