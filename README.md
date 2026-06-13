# Techychat

Private 1-on-1 messaging app. Email-based accounts secured by PIN only.  
Built with vanilla HTML/CSS/JS + Supabase (Auth, Realtime, Storage).

---

## File Structure

```
techychat/
├── auth.html            ← Login + Sign-up (combined)
├── messages.html        ← Chat list
├── chat.html            ← 1-on-1 chat window
├── posts.html           ← Friends feed
├── friends.html         ← Friends, requests, search
├── notifications.html   ← Notification centre
├── profile.html         ← Edit profile, away mode, delete account
├── user-profile.html    ← View another user's profile
├── contact.html         ← Contact form + direct links
├── css/
│   └── main.css         ← All styles (dark + light mode)
├── js/
│   └── app.js           ← Supabase client + all shared utilities
├── assets/
│   ├── icon.svg
│   ├── icon-192.png
│   └── icon-512.png
├── sw.js                ← Service worker (PWA / offline)
├── manifest.json        ← PWA manifest
├── schema.sql           ← Complete Supabase schema (run once)
└── .env.example         ← Environment variable template
```

---

## Setup (5 steps)

### 1 — Create a Supabase project

Go to [supabase.com](https://supabase.com) → New Project. Note your **Project URL** and **anon key** from  
Settings → API.

### 2 — Run the schema

Supabase Dashboard → **SQL Editor** → New Query → paste the entire contents of `schema.sql` → **Run**.

This single script:
- Creates all tables with RLS policies
- Creates the `media` storage bucket with upload policies
- Sets up Realtime subscriptions
- Adds triggers (auto-create profile on sign-up, updated_at)
- Registers the `delete_own_account` RPC function

**No other dashboard configuration is needed.**

### 3 — Configure your keys

Open `js/app.js` and replace lines 3–4:

```js
const SUPABASE_URL      = 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
```

### 4 — Enable Email OTP in Supabase

Dashboard → Authentication → Providers → **Email** → enable  
**"Magic Link / OTP"** (this is on by default).  
Optionally configure your SMTP server under Auth → SMTP Settings for production.

### 5 — Deploy

**Netlify (recommended):**  
Drag the entire `techychat/` folder to [app.netlify.com/drop](https://app.netlify.com/drop). Done.

**Vercel:**
```bash
npm i -g vercel
cd techychat
vercel --prod
```

**Local (for dev):**
```bash
npx serve .
# open http://localhost:3000/auth.html
```

---

## Features

| Feature | Detail |
|---|---|
| Auth | Email OTP → PIN (4–6 digits, bcrypt hashed) |
| Forgot PIN | Re-verify email → set new PIN |
| Delete Account | Confirmed with typed "DELETE" → cascade deletes all data |
| Messaging | 1-on-1, text + images, read receipts, realtime |
| Auto-reply | Away mode with custom message |
| Posts | Text + image, likes, comments, friends-only feed |
| Friends | Search by email/name, request flow, block/unfriend |
| Notifications | Realtime bell for messages, likes, comments, requests |
| Storage | 5 MB limit, JPEG/PNG/WebP/GIF, auto-compressed |
| PWA | Installable, offline shell, home screen shortcut |
| Dark / Light | Toggle in top nav, persisted to localStorage |

---

## Auth Flow

```
New user:  Email → OTP code → Display name → Set PIN → messages.html
Returning: Email → OTP code → Enter PIN    → messages.html
Forgot:    Email → OTP code → New PIN      → messages.html
```

---

## Security Notes

- PINs are **never stored in plain text** — bcrypt (cost 10) only.
- RLS policies enforce that users can only read/write their own data or their friends' data.
- Storage policies restrict uploads to the authenticated user's own folder.
- The `delete_own_account` SQL function can only be called by the authenticated user themselves.
- Inactivity auto-logout after 30 minutes.

---

## Customisation

| What | Where |
|---|---|
| App name | Find/replace "Techychat" across all `.html` files |
| Accent colour | `css/main.css` → `--accent: #6c63ff` |
| Support email | `contact.html` → `mailto:` link |
| WhatsApp number | `contact.html` → `wa.me/` link |
| Inactivity timeout | `js/app.js` → `Idle.LIMIT` |
| Auto-logout | `js/app.js` → `Auth.logout()` |
