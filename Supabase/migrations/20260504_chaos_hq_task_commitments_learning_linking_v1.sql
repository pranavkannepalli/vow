-- ChaosHQ: link tasks <-> commitments & learnings (schema + migrations)
-- Creates:
-- - public.task_commitment_links join table
-- - public.task_learning_links join table

begin;

-- Join table linking a ChaosHQ/VowCore `tasks` row to one or more `commitments`.
create table if not exists public.task_commitment_links (
  id uuid primary key default gen_random_uuid(),

  task_id uuid not null references public.tasks(id) on delete cascade,
  commitment_id uuid not null references public.commitments(id) on delete cascade,

  -- Relative role of the commitment for this task (e.g. implements, depends_on, said_id_do).
  link_role text default 'commitment',

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (task_id, commitment_id, link_role)
);

create index if not exists task_commitment_links_task_idx
  on public.task_commitment_links(task_id);

create index if not exists task_commitment_links_commitment_idx
  on public.task_commitment_links(commitment_id);

-- Join table linking a ChaosHQ/VowCore `tasks` row to one or more `learning` items.
create table if not exists public.task_learning_links (
  id uuid primary key default gen_random_uuid(),

  task_id uuid not null references public.tasks(id) on delete cascade,
  learning_id uuid not null references public.learning(id) on delete cascade,

  -- Relative role of the learning for this task (e.g. reference, prerequisite, informed_design).
  link_role text default 'learning_reference',

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (task_id, learning_id, link_role)
);

create index if not exists task_learning_links_task_idx
  on public.task_learning_links(task_id);

create index if not exists task_learning_links_learning_idx
  on public.task_learning_links(learning_id);

-- Disable RLS for these new tables (matching the overall “builder” schema approach).
alter table public.task_commitment_links disable row level security;
alter table public.task_learning_links disable row level security;

commit;
