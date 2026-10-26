-- APAAR Sentinel: fresh schema for an academic prototype.
-- Run in Supabase SQL Editor. No official APAAR/AICTE integration is implied.
create extension if not exists pgcrypto;

create type public.app_role as enum ('administrator','data_manager','viewer');
create type public.record_status as enum ('valid','review_required','duplicate_candidate');
create type public.issue_status as enum ('open','reviewed','resolved');

create table public.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  institution_identifier text not null unique,
  contact_email text,
  contact_phone text,
  approved_intake integer not null default 0 check (approved_intake >= 0),
  actual_enrolment integer not null default 0 check (actual_enrolment >= 0),
  supernumerary_seats integer not null default 0 check (supernumerary_seats >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null,
  role public.app_role not null default 'viewer',
  institution_id uuid references public.institutions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  student_name text not null check (length(trim(student_name)) > 0),
  apaar_id text not null check (length(trim(apaar_id)) > 0),
  institution_id uuid not null references public.institutions(id) on delete restrict,
  academic_year text not null,
  programme text not null,
  department text,
  semester integer check (semester is null or semester between 1 and 20),
  enrolment_year integer not null check (enrolment_year between 1900 and 2200),
  nri_category boolean not null default false,
  oci_status boolean not null default false,
  fn_status boolean not null default false,
  record_status public.record_status not null default 'valid',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Project-level uniqueness rule. Duplicate candidates are surfaced during import before insert.
  unique (apaar_id)
);
create index students_name_idx on public.students using btree (student_name);
create index students_institution_idx on public.students (institution_id);
create index students_year_idx on public.students (academic_year);
create index students_status_idx on public.students (record_status);

create table public.verification_issues (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete set null,
  issue_type text not null,
  description text not null,
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  review_status public.issue_status not null default 'open',
  reviewer_notes text,
  detected_at timestamptz not null default now(),
  resolved_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null
);
create index verification_status_idx on public.verification_issues (review_status, detected_at desc);
create index verification_student_idx on public.verification_issues (student_id);

create table public.upload_jobs (
  id uuid primary key default gen_random_uuid(),
  original_filename text not null,
  institution_id uuid not null references public.institutions(id) on delete restrict,
  uploaded_by uuid references auth.users(id) on delete set null,
  total_rows integer not null default 0 check (total_rows >= 0),
  imported_rows integer not null default 0 check (imported_rows >= 0),
  rejected_rows integer not null default 0 check (rejected_rows >= 0),
  upload_status text not null default 'pending' check (upload_status in ('pending','processing','completed','completed_with_errors','failed')),
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  description text not null default '',
  outcome text not null default 'success',
  created_at timestamptz not null default now()
);
create index audit_created_idx on public.audit_logs (created_at desc);
create index audit_entity_idx on public.audit_logs (entity_type, entity_id);

create or replace function public.current_role()
returns public.app_role language sql stable security definer set search_path=public
as $$ select role from public.profiles where id = auth.uid() $$;
create or replace function public.current_institution()
returns uuid language sql stable security definer set search_path=public
as $$ select institution_id from public.profiles where id = auth.uid() $$;
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce(public.current_role() = 'administrator', false) $$;

-- Profile creation is limited to safe self-profile creation. Role is always viewer;
-- administrators assign elevated roles/institution via a trusted administrative process.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id, full_name, email, role)
  values(new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email, 'viewer')
  on conflict (id) do nothing;
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path=public
as $$ begin new.updated_at=now(); return new; end; $$;
create trigger institutions_touch before update on public.institutions for each row execute procedure public.touch_updated_at();
create trigger profiles_touch before update on public.profiles for each row execute procedure public.touch_updated_at();
create trigger students_touch before update on public.students for each row execute procedure public.touch_updated_at();

-- Immutable audit rows for core table changes, created inside PostgreSQL.
create or replace function public.audit_row_change()
returns trigger language plpgsql security definer set search_path=public
as $$
declare rec jsonb; eid text; act text; descr text;
begin
  if TG_OP='DELETE' then rec=to_jsonb(old); else rec=to_jsonb(new); end if;
  eid=coalesce(rec->>'id','');
  act=lower(TG_OP);
  descr=TG_TABLE_NAME||' record '||act;
  insert into public.audit_logs(user_id,action,entity_type,entity_id,description,outcome)
  values(auth.uid(),act,TG_TABLE_NAME,eid,descr,'success');
  if TG_OP='DELETE' then return old; else return new; end if;
end; $$;
create trigger audit_students after insert or update or delete on public.students for each row execute procedure public.audit_row_change();
create trigger audit_institutions after insert or update or delete on public.institutions for each row execute procedure public.audit_row_change();
create trigger audit_verification after insert or update on public.verification_issues for each row execute procedure public.audit_row_change();
create trigger audit_upload_jobs after insert or update on public.upload_jobs for each row execute procedure public.audit_row_change();

alter table public.profiles enable row level security;
alter table public.institutions enable row level security;
alter table public.students enable row level security;
alter table public.verification_issues enable row level security;
alter table public.upload_jobs enable row level security;
alter table public.audit_logs enable row level security;

create policy "profiles read self or admin" on public.profiles for select to authenticated
using (id=auth.uid() or public.is_admin());
create policy "profile self update limited" on public.profiles for update to authenticated
using (id=auth.uid() and role='viewer') with check (id=auth.uid() and role='viewer');
create policy "admins manage profiles" on public.profiles for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "institutions readable by signed in users" on public.institutions for select to authenticated
using (public.is_admin() or id=public.current_institution());
create policy "admins manage institutions" on public.institutions for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "students scoped read" on public.students for select to authenticated
using (public.is_admin() or institution_id=public.current_institution());
create policy "students scoped insert" on public.students for insert to authenticated
with check ((public.is_admin() or (public.current_role()='data_manager' and institution_id=public.current_institution())) and (created_by is null or created_by=auth.uid()));
create policy "students scoped update" on public.students for update to authenticated
using (public.is_admin() or (public.current_role()='data_manager' and institution_id=public.current_institution()))
with check (public.is_admin() or (public.current_role()='data_manager' and institution_id=public.current_institution()));
create policy "students scoped delete" on public.students for delete to authenticated
using (public.is_admin() or (public.current_role()='data_manager' and institution_id=public.current_institution()));

create policy "issues scoped read" on public.verification_issues for select to authenticated
using (public.is_admin() or (student_id is not null and exists(select 1 from public.students s where s.id=student_id and s.institution_id=public.current_institution())));
create policy "issues scoped insert" on public.verification_issues for insert to authenticated
with check (public.is_admin() or (public.current_role()='data_manager' and student_id is not null and exists(select 1 from public.students s where s.id=student_id and s.institution_id=public.current_institution())));
create policy "issues scoped update" on public.verification_issues for update to authenticated
using (public.is_admin() or (public.current_role()='data_manager' and student_id is not null and exists(select 1 from public.students s where s.id=student_id and s.institution_id=public.current_institution())))
with check (public.is_admin() or (public.current_role()='data_manager' and student_id is not null and exists(select 1 from public.students s where s.id=student_id and s.institution_id=public.current_institution())));

create policy "uploads scoped read" on public.upload_jobs for select to authenticated
using (public.is_admin() or institution_id=public.current_institution());
create policy "uploads scoped insert" on public.upload_jobs for insert to authenticated
with check ((public.is_admin() or (public.current_role()='data_manager' and institution_id=public.current_institution())) and (uploaded_by is null or uploaded_by=auth.uid()));
create policy "uploads scoped update" on public.upload_jobs for update to authenticated
using (public.is_admin() or (public.current_role()='data_manager' and institution_id=public.current_institution()))
with check (public.is_admin() or (public.current_role()='data_manager' and institution_id=public.current_institution()));

create policy "audit read admin and manager scoped" on public.audit_logs for select to authenticated
using (public.is_admin() or (public.current_role()='data_manager' and user_id=auth.uid()));
-- Deliberately no client insert/update/delete policy for audit_logs.

-- Admin bootstrap:
-- Register your first account in the app. Then, in Supabase SQL Editor, identify its auth.users id
-- and run this once, substituting the UUID and an existing institution UUID after creating it:
-- update public.profiles set role='administrator' where id='YOUR-AUTH-USER-UUID';
-- Do not expose a service-role key in the browser. Assign manager role and institution_id only through trusted admin operations.
