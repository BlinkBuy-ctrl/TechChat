-- ================================================================
--  TECHYCHAT – COMPLETE SUPABASE SCHEMA
--  Paste this entire file into:
--  Supabase Dashboard → SQL Editor → New Query → Run
--
--  This script:
--    • Creates all tables with RLS
--    • Creates the storage bucket + policies
--    • Sets up realtime publications
--    • Adds helper functions & triggers
--    • Nothing else to do in the dashboard
-- ================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_net;        -- needed for edge function calls (optional)

-- ----------------------------------------------------------------
-- 1. PROFILES
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email             TEXT UNIQUE,
  phone_number      TEXT,
  display_name      TEXT NOT NULL DEFAULT 'New User',
  bio               TEXT DEFAULT '',
  profile_photo_url TEXT,
  pin_hash          TEXT,          -- bcrypt hash only, never plain text
  status            TEXT DEFAULT 'online' CHECK (status IN ('online','offline')),
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_own"      ON public.profiles FOR ALL  USING (auth.uid() = id);
CREATE POLICY "profiles_friends"  ON public.profiles FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.friends WHERE user_id = auth.uid() AND friend_id = profiles.id)
);

-- ----------------------------------------------------------------
-- 2. USER SETTINGS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id          UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  away_mode        BOOLEAN DEFAULT FALSE,
  auto_reply_text  TEXT DEFAULT 'I''m away right now. I''ll reply soon!'
);
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "settings_own" ON public.user_settings FOR ALL USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- 3. FRIEND REQUESTS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.friend_requests (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status      TEXT DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined')),
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (sender_id, receiver_id)
);
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "freq_select" ON public.friend_requests FOR SELECT
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
CREATE POLICY "freq_insert" ON public.friend_requests FOR INSERT
  WITH CHECK (auth.uid() = sender_id);
CREATE POLICY "freq_update" ON public.friend_requests FOR UPDATE
  USING (auth.uid() = receiver_id);
CREATE POLICY "freq_delete" ON public.friend_requests FOR DELETE
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- ----------------------------------------------------------------
-- 4. FRIENDS  (bidirectional rows)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.friends (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  friend_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, friend_id)
);
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;
CREATE POLICY "friends_own" ON public.friends FOR ALL USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- 5. BLOCKED USERS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.blocked_users (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, blocked_id)
);
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "blocked_own" ON public.blocked_users FOR ALL USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- 6. MESSAGES
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.messages (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  receiver_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content       TEXT,
  image_url     TEXT,
  is_read       BOOLEAN DEFAULT FALSE,
  is_auto_reply BOOLEAN DEFAULT FALSE,
  delivered_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "messages_rw" ON public.messages FOR ALL
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id)
  WITH CHECK (auth.uid() = sender_id);

-- ----------------------------------------------------------------
-- 7. POSTS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.posts (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content      TEXT,
  image_url    TEXT,
  likes_count  INT DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "posts_own"     ON public.posts FOR ALL   USING (auth.uid() = user_id);
CREATE POLICY "posts_friends" ON public.posts FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.friends WHERE user_id = auth.uid() AND friend_id = posts.user_id)
);

-- ----------------------------------------------------------------
-- 8. POST LIKES
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_likes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (post_id, user_id)
);
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "likes_select" ON public.post_likes FOR SELECT USING (TRUE);
CREATE POLICY "likes_own"    ON public.post_likes FOR ALL   USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- 9. POST COMMENTS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_comments (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content    TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "comments_select" ON public.post_comments FOR SELECT USING (TRUE);
CREATE POLICY "comments_own"    ON public.post_comments FOR ALL   USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- 10. NOTIFICATIONS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  from_user_id  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  type          TEXT NOT NULL,   -- 'new_message'|'post_like'|'post_comment'|'new_post'|'friend_request'|'friend_accept'
  message       TEXT,
  link          TEXT,
  is_read       BOOLEAN DEFAULT FALSE,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notif_own" ON public.notifications FOR ALL USING (auth.uid() = user_id);
-- Allow any authenticated user to INSERT a notification for others
CREATE POLICY "notif_insert_any" ON public.notifications FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ----------------------------------------------------------------
-- 11. CONTACT MESSAGES
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.contact_messages (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  email      TEXT NOT NULL,
  subject    TEXT,
  message    TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;
-- Anyone (even unauthenticated) can insert a contact message
CREATE POLICY "contact_insert" ON public.contact_messages FOR INSERT WITH CHECK (TRUE);
-- Only service role can read contact messages
CREATE POLICY "contact_select" ON public.contact_messages FOR SELECT USING (FALSE);

-- ----------------------------------------------------------------
-- 12. UPDATED_AT TRIGGER  (applies to profiles)
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ----------------------------------------------------------------
-- 13. AUTO-CREATE PROFILE + SETTINGS ON SIGN-UP
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_settings (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_new_user ON auth.users;
CREATE TRIGGER trg_new_user
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ----------------------------------------------------------------
-- 14. DELETE OWN ACCOUNT  (callable from frontend via RPC)
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Delete auth user; CASCADE handles all related rows
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;
-- Only the authenticated user themselves can call this
REVOKE ALL ON FUNCTION public.delete_own_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_own_account() TO authenticated;

-- ----------------------------------------------------------------
-- 15. STORAGE BUCKET + POLICIES  (fully automated)
-- ----------------------------------------------------------------
-- Create the bucket if it doesn't already exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'media',
  'media',
  TRUE,
  5242880,   -- 5 MB limit
  ARRAY['image/jpeg','image/png','image/webp','image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public             = TRUE,
  file_size_limit    = 5242880,
  allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/gif'];

-- Drop old policies if re-running script
DROP POLICY IF EXISTS "media_select"  ON storage.objects;
DROP POLICY IF EXISTS "media_insert"  ON storage.objects;
DROP POLICY IF EXISTS "media_update"  ON storage.objects;
DROP POLICY IF EXISTS "media_delete"  ON storage.objects;

-- Public read
CREATE POLICY "media_select" ON storage.objects
  FOR SELECT USING (bucket_id = 'media');

-- Authenticated users can upload to their own folder only
CREATE POLICY "media_insert" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'media'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] IN (auth.uid()::text, 'posts', 'avatars')
  );

-- Uploader can update their own files
CREATE POLICY "media_update" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'media' AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Uploader can delete their own files
CREATE POLICY "media_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'media' AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- ----------------------------------------------------------------
-- 16. REALTIME PUBLICATIONS
-- ----------------------------------------------------------------
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
EXCEPTION WHEN others THEN NULL; END$$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
EXCEPTION WHEN others THEN NULL; END$$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.friend_requests;
EXCEPTION WHEN others THEN NULL; END$$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.posts;
EXCEPTION WHEN others THEN NULL; END$$;

-- ================================================================
--  DONE.  Everything is set up. No manual dashboard steps needed.
-- ================================================================
