-- Vow v2 schema migration
-- Adds tables for:
-- - Life tracker (daily score inputs + penalties)
-- - Atomic habits (definitions + daily instances)
-- - Screen-control / session observation events

begin;

-- Users table (app-level). Note: Supabase auth users live in auth.users; this is an app mirror.
create table if not exists public.users (
  id uuid primary key,
  created_at timestamptz not null default now(),
  timezone text,
  settings_blob jsonb not null default '{}'::jsonb
);

-- Life tracker inputs (one row per user per day)
create table if not exists public.life_tracker_days (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  date date not null,

  movement_points double precision not null default 0,
  focus_points double precision not null default 0,
  journal_points double precision not null default 0,
  sleep_regularity_points double precision,

  high_risk_usage_penalty double precision not null default 0,
  overrun_penalty double precision not null default 0,
  late_night_penalty double precision not null default 0,
  repeated_request_penalty double precision not null default 0,

  -- total score (reduces client compute variance when formulas evolve)
  total_score double precision,
  breakdown_json jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (user_id, date)
);

create index if not exists life_tracker_days_user_date_idx
  on public.life_tracker_days(user_id, date);

-- Atomic habit definitions
create table if not exists public.atomic_habit_definitions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,

  name text not null,

  -- e.g. "focus_sessions_completed", "journal_completed", etc.
  habit_kind text not null default 'generic',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (user_id, name)
);

create index if not exists atomic_habit_definitions_user_idx
  on public.atomic_habit_definitions(user_id);

-- Atomic habit instances (one row per user per habit per day)
create table if not exists public.atomic_habit_instances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  habit_definition_id uuid not null references public.atomic_habit_definitions(id) on delete cascade,

  date date not null,

  status text not null default 'not_started' check (status in ('not_started','in_progress','completed')),

  completed_at timestamptz,
  occurrence_count int not null default 0,

  -- For audit/debug: what evidence contributed to completion
  evidence_json jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (user_id, habit_definition_id, date)
);

create index if not exists atomic_habit_instances_user_date_idx
  on public.atomic_habit_instances(user_id, date);

-- Focus session records (evidence task observation)
create table if not exists public.focus_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,

  -- Optional link to the unlock request that triggered/required this session
  request_id uuid,

  started_at timestamptz not null,
  ended_at timestamptz,

  target_seconds int not null default 0,
  actual_seconds int,

  allows_pause boolean not null default false,
  interrupted boolean not null default false,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists focus_sessions_user_time_idx
  on public.focus_sessions(user_id, started_at desc);

-- Screen control / session observation event log
create table if not exists public.screen_control_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,

  occurred_at timestamptz not null default now(),

  event_type text not null,

  -- Link to unlock request or null for system-initiated events
  request_id uuid,

  -- Arbitrary details (shield reason, target label, duration, classification, etc.)
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists screen_control_events_user_time_idx
  on public.screen_control_events(user_id, occurred_at desc);

create index if not exists screen_control_events_user_request_idx
  on public.screen_control_events(user_id, request_id);

commit;
