# openai-proxy (valfritt backend för AI-coachen)

En enda Python-fil (standardbiblioteket räcker) som vidarebefordrar
`POST /v1/chat/completions` till en OpenAI-kompatibel tjänst — **med SSE-
streaming bevarad** — utan att API-nyckeln någonsin finns i appen.

## Varför

Appens regelverk är tydligt:

- ingen API-nyckel får följa med i en IPA (IPAs distribueras osignerade och
  kan packas upp av vem som helst),
- demoläget (`DemoCoachService`) kör helt lokalt när ingen server är satt.

Den här proxyn är mellanstadiet: nyckeln bor på din server, appen pratar med
den över HTTPS.

## Köra lokalt (test)

```bash
PORT=8080 UPSTREAM_KEY=sk-... python3 server.py
curl localhost:8080/healthz
```

I appen: Inställningar → AI-backend → Server-URL `http://<datorns-ip>:8080`.
(Obs: appen kräver `https://` i produktionsläge — lokala test med http måste
hanteras via ATS-undantag, vilket projektet inte sätter. Använd därför en
https-tunnel som `ngrok http 8080` eller `cloudflared tunnel --url localhost:8080`
för lokal testning.)

## Deploy

Exempel med Fly.io (fungerar liknande på Railway/Render/Koyeb):

```bash
cd backend/openai-proxy
fly launch --no-deploy --name din-proxy
fly secrets set UPSTREAM_KEY=sk-... PROXY_TOKEN=välj-en-lång-slumpsträng
fly deploy
```

App-URL:en blir `https://din-proxy.fly.dev`. Den använder Let's Encrypt,
så https kravet är uppfyllt direkt.

## Miljövariabler

| Variabel        | Krävs | Beskrivning                                                     |
|-----------------|-------|-----------------------------------------------------------------|
| `UPSTREAM_KEY`  | ja    | Riktiga API-nyckeln mot OpenAI (eller kompatibel tjänst).       |
| `UPSTREAM_URL`  | nej   | `https://api.openai.com` som standard.                          |
| `PROXY_TOKEN`   | nej   | Delad hemlighet. Om satt kräver proxyn `Authorization: Bearer <token>` från appen. |
| `MODEL_OVERRIDE`| nej   | Tvingar en modell oavsett vad appen ber om.                     |
| `PORT`          | nej   | 8080 som standard.                                              |

## I appen

1. Inställningar → AI-backend → Server-URL: `https://din-proxy.fly.dev`
2. Modell: t.ex. `gpt-4o-mini`
3. Kräv API-nyckel: på, och klistra in `PROXY_TOKEN` (den *delade* hemligheten, inte sk-nyckeln)
4. Testa anslutningen

Nyckeln sparas i enhetens Keychain (`kSecAttrAccessibleAfterFirstUnlock`),
aldrig i filer, aldrig i exporten.
