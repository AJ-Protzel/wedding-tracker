-- Wedding Tracker: the whole database.
-- Paste into a new Supabase project's SQL editor and run it once.
--
-- Every table has row-level security on and no policies, so the publishable key
-- in index.html reads nothing directly. The page only calls the three functions
-- at the bottom, and each refuses anyone who is not signed in.

-- ---------------------------------------------------------------- tables

create table settings (
  key   text primary key,
  value text not null,
  note  text
);

create table transaction_groups (
  id         serial primary key,
  name       text not null unique,
  details    text,
  sort_order int not null default 100
);

create table beds (
  id         text primary key,             -- e.g. 1.2 = building 1, bed 2
  cabin      text not null,                -- "Main lodge — upstairs": text after " — " becomes a floor heading
  bed_type   text not null,
  capacity   int  not null default 2,
  sort_order int
);

create table guests (
  id               serial primary key,
  name             text not null,
  party            int,                    -- guests sharing a party are drawn tied together
  is_international boolean not null default false,
  attending        boolean not null default true,
  pays             boolean not null default true,   -- false: you cover them
  bed_id           text references beds(id),
  notes            text,
  rsvp             text not null default 'pending' check (rsvp in ('yes','no','pending')),
  is_pet           boolean not null default false,  -- takes a bed, is no guest and no plate
  eats_dinner      boolean not null default true
);

create table vendors (
  id              serial primary key,
  name            text not null,
  role            text not null,
  company         text,
  headcount       int not null default 1,
  eats_dinner     boolean not null default false,
  on_site         boolean not null default true,
  contract_status text,
  notes           text
);

-- Money out (paid, due) and money in (received), one row each.
create table transactions (
  id              serial primary key,
  status          text not null check (status in ('paid','due','received')),
  group_id        int  not null references transaction_groups(id),
  due_date        date,                    -- drives "in 12d" / "overdue"
  date_label      text,                    -- the date as shown
  category        text,                    -- 'Gift' puts money in on the Gifts page
  company         text,
  label           text,
  amount          numeric(12,2),           -- always in the page's home currency, never negative
  amount_note     text,
  details         text,
  refundable      boolean not null default false,   -- listed, left out of every total
  part_num        int,
  part_total      int,                     -- instalments show as (1/2), (2/2)
  guest_id        int references guests(id),        -- a received row with a guest marks them paid
  currency        text not null default 'USD',
  amount_original numeric,                 -- the amount in currency, when it is not the home one
  gift_via        text,
  gift_side       text
);

-- Money someone has said they will give but hasn't yet. Shown, never counted.
create table money_promised (
  id              bigint generated always as identity primary key,
  label           text not null,
  vendor          text,
  amount          numeric check (amount >= 0),
  item_date       date,
  date_label      text,
  is_estimate     boolean not null default false,
  details         text,
  group_id        int not null references transaction_groups(id),
  covers_group_id int references transaction_groups(id),  -- covers a whole group: amount stays null
  created_at      timestamptz not null default now()
);

create table page_text (
  key        text primary key,               -- 'timeline' and 'notes'
  html       text not null,
  updated_at timestamptz not null default now()
);

create table checklist_items (
  id         bigint generated always as identity primary key,
  list       text not null,                  -- the section, e.g. To Buy
  sublist    text,                           -- "Heading · small grey text"
  body       text not null,
  note       text,
  done       boolean not null default false,
  done_at    timestamptz,
  done_by    text,
  sort_order int not null,
  created_at timestamptz not null default now()
);

create table unsorted_notes (
  id         bigint generated always as identity primary key,
  body       text not null check (length(btrim(body)) between 1 and 1000),
  added_by   text,
  created_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['settings','transaction_groups','beds','guests','vendors','transactions',
                           'money_promised','page_text','checklist_items','unsorted_notes'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- views

create view money_summary with (security_invoker = true) as
select coalesce(sum(amount) filter (where status = 'paid'), 0) as paid,
       coalesce(sum(amount) filter (where status = 'due' and not refundable), 0) as due,
       coalesce(sum(amount) filter (where status = 'due' and refundable), 0) as refundable_due,
       coalesce(sum(amount) filter (where status in ('paid','due') and not refundable), 0) as committed,
       count(*) filter (where status = 'due' and amount is null)::int as unpriced_due,
       count(*) filter (where status = 'due')::int as due_items,
       coalesce(sum(amount) filter (where status = 'received'), 0) as received
  from transactions;

create view lodging with (security_invoker = true) as
select b.id, b.cabin, b.bed_type, b.sort_order,
       (count(g.id) filter (where not g.is_pet))::int as people,
       count(g.id)::int as bodies,
       coalesce(string_agg(g.name, ', ' order by g.is_pet, g.name), '') as names
  from beds b
  left join guests g on g.bed_id = b.id and g.attending
 group by b.id, b.cabin, b.bed_type, b.sort_order;

create view lodging_summary with (security_invoker = true) as
select (select count(*) from beds)::int as bed_count,
       (select count(distinct bed_id) from guests where attending and bed_id is not null)::int as beds_used,
       (select count(*) from guests where attending and not is_pet)::int as guests_attending,
       (select count(distinct party) from guests where attending and not is_pet)::int as parties_attending,
       (select count(*) from guests where attending and not is_pet and bed_id is not null)::int as guests_placed,
       (select count(*) from guests where attending and not is_pet and rsvp = 'yes')::int as rsvped,
       ((select count(*) from guests where attending and not is_pet and eats_dinner)
        + coalesce((select sum(headcount) from vendors where eats_dinner), 0))::int as dinner_count,
       (select count(*) from guests where attending and not is_pet and pays)::int as payers;

revoke all on money_summary, lodging, lodging_summary from anon, authenticated;

-- ---------------------------------------------------------------- the page's functions

-- Everything the page draws, as one JSON object, to signed-in users only.
create or replace function tracker_data()
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  return json_build_object(
    'money', (select row_to_json(m) from money_summary m),
    'lodging', (select json_agg(row_to_json(l) order by l.sort_order) from lodging l),
    'lodging_summary', (select row_to_json(s) from lodging_summary s),
    'guests', (select json_agg(json_build_object('id', id, 'name', name, 'party', party,
                 'is_international', is_international, 'attending', attending, 'pays', pays,
                 'bed_id', bed_id, 'rsvp', rsvp, 'is_pet', is_pet) order by id) from guests),
    'vendors', (select json_agg(row_to_json(v) order by v.id) from vendors v),
    'transactions', (select json_agg(row_to_json(t) order by t.id) from transactions t),
    'tx_groups', (select json_agg(row_to_json(g) order by g.sort_order, g.id) from transaction_groups g),
    'settings', (select json_object_agg(key, value) from settings),
    'page_text', (select json_object_agg(key, html) from page_text),
    'unsorted_notes', (select json_agg(json_build_object('id', n.id, 'body', n.body, 'created_at', n.created_at)
                         order by n.created_at) from unsorted_notes n),
    -- a promise to cover a whole group reads its amount from that group's paid and due rows
    'money_promised', (select json_agg(row_to_json(p) order by p.item_date nulls last, p.id) from (
        select mp.id, mp.label, mp.vendor,
               coalesce(mp.amount, (select sum(t.amount) from transactions t
                                     where t.group_id = mp.covers_group_id and t.status in ('paid','due')
                                       and not t.refundable)) as amount,
               mp.item_date, mp.date_label, mp.is_estimate, mp.details, mp.group_id, mp.covers_group_id
          from money_promised mp) p),
    'checklist', (select json_agg(json_build_object('id', c.id, 'list', c.list, 'sublist', c.sublist,
                    'body', c.body, 'note', c.note, 'done', c.done) order by c.sort_order, c.id)
                  from checklist_items c)
  );
end;
$$;

-- Ticks or unticks one checklist item and records who did it.
create or replace function set_checklist_item(item_id bigint, is_done boolean)
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare r checklist_items;
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  update checklist_items
     set done = coalesce(is_done, false),
         done_at = case when is_done then now() end,
         done_by = case when is_done then auth.jwt() ->> 'email' end
   where id = item_id
  returning * into r;
  return json_build_object('id', r.id, 'done', r.done);
end;
$$;

-- Adds a line to Unsorted Notes.
create or replace function add_unsorted_note(note text)
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare r unsorted_notes;
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  insert into unsorted_notes (body, added_by)
  values (btrim(note), auth.jwt() ->> 'email')
  returning * into r;
  return json_build_object('id', r.id, 'body', r.body, 'created_at', r.created_at);
end;
$$;

revoke execute on function tracker_data(), set_checklist_item(bigint, boolean), add_unsorted_note(text) from public, anon;
grant execute on function tracker_data(), set_checklist_item(bigint, boolean), add_unsorted_note(text) to authenticated;

-- ---------------------------------------------------------------- starting settings

insert into settings (key, value, note) values
  ('site_title', 'Our Wedding', 'The page title'),
  ('venue', 'Your venue, Town', 'Shown above the title'),
  ('wedding_date', '2027-06-12', 'YYYY-MM-DD'),
  ('ask_per_person', '0', 'What each paying guest is asked to contribute'),
  ('ask_note', '', 'A line shown after the per-person amount'),
  ('family_tab', '', 'The Money In group to follow as a family tab; empty hides it'),
  ('ceremony_musicians', '0', 'Used by data-calc="ceremony_chairs"'),
  ('ceremony_standing', '2', 'People standing up front, also for ceremony_chairs');

insert into page_text (key, html) values
  ('timeline', '<section><div class="sectitle"><h2>Timeline</h2></div><div class="kv"><div>Write your timeline here.</div></div></section>'),
  ('notes', '<section><div class="sectitle"><h2>Notes</h2></div><div class="kv"><div>Guests: <span data-calc="guests"></span></div></div></section>');
