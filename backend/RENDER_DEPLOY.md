# Deploy FastAPI to Render

## 1) Create a PostgreSQL database on Render
- In Render, create a **PostgreSQL** instance.
- Copy the **Internal Database URL** and set it as `DATABASE_URL` on your web service.

## 2) Create the web service
- Connect this repo in Render and use the included `render.yaml` blueprint, or set manually:
  - **Root Directory:** `backend`
  - **Build Command:** `pip install -r requirements.txt`
  - **Start Command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`
  - **Health Check Path:** `/health`

## 3) Required environment variables
Set these in Render (Environment tab):
- `DATABASE_URL` (Render Postgres URL)
- `SECRET_KEY` (JWT signing key, use a strong random value)

Optional for card payments:
- `STRIPE_SECRET_KEY`
- `STRIPE_PUBLISHABLE_KEY`
- `STRIPE_WEBHOOK_SECRET`

## 4) Stripe webhook (optional card flow)
- In Stripe dashboard, add webhook endpoint:
  - `https://<your-service>.onrender.com/webhooks/stripe`
- Subscribe to `payment_intent.succeeded`.
- Paste Stripe webhook signing secret into `STRIPE_WEBHOOK_SECRET`.

## 5) Point Flutter app to Render API
Run mobile app with:

```bash
flutter run --dart-define=API_BASE=https://<your-service>.onrender.com
```

Or set API base in your release pipeline similarly.

## Notes
- SQLite is not recommended on Render web services because the filesystem is ephemeral. Use Postgres via `DATABASE_URL`.
- CORS already allows `*.onrender.com` plus localhost/LAN dev hosts.