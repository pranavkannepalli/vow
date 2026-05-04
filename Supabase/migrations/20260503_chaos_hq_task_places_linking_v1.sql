-- ChaosHQ: link tasks <-> places (schema + migrations)
-- Creates:
-- - public.places
-- - public.task_place_links join table

begin;

-- Ensure crypto is available for UUID generation.
create extension if not exists pgcrypto;

-- places
create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),

  -- Human-readable label for the place/evidence source.
  name text not null,

  -- Categorization for downstream reasoning/UI.
  place_type text default 'generic' check (
    place_type in ('generic','physical','virtual','journal','focus_session','screen')
  ),

  -- Optional scoping (if you want to reuse the same schema across domains).
  domain text,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists places_place_type_idx
  on public.places(place_type);

-- task_place_links
-- Join table linking a ChaosHQ/VowCore `tasks` row to one or more `places`.
create table if not exists public.task_place_links (
  id uuid primary key default gen_random_uuid(),

  task_id uuid not null references public.tasks(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,

  -- Relative role of the place for this task (e.g. evidence_source, checklist_step, etc.)
  link_role text default 'evidence_source',

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (task_id, place_id, link_role)
);

create index if not exists task_place_links_task_idx
  on public.task_place_links(task_id);

create index if not exists task_place_links_place_idx
  on public.task_place_links(place_id);

-- Disable RLS for these new tables (matching the overall “builder” schema approach).
alter table public.places disable row level security;
alter table public.task_place_links disable row level security;

commit;
