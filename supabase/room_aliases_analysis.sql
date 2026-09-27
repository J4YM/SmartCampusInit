-- Room alias INSERTs derived from the real distinct-room-name output you
-- ran (Part 1's second query, against class_section_meetings). Two
-- families of aliases below, plus a list of things aliasing genuinely
-- can't fix — read that section before assuming this covers everything.

-- ---------------------------------------------------------------------------
-- Family 1: ComLab / COM LAB / Comlab / CompLab / COMPUTER LABORATORY —
-- five different spelling conventions for the same three computer labs.
-- Canonical form: "COMPUTER LABORATORY N" (the Room Schedule file's own
-- official room-header wording).
-- ---------------------------------------------------------------------------

insert into public.room_aliases (alias, canonical_room)
values
  ('ComLab 1', 'COMPUTER LABORATORY 1'),
  ('Comlab1', 'COMPUTER LABORATORY 1'),
  ('ComLab 2', 'COMPUTER LABORATORY 2'),
  ('COM LAB 2', 'COMPUTER LABORATORY 2'),
  ('ComLab 3', 'COMPUTER LABORATORY 3'),
  ('Comlab3', 'COMPUTER LABORATORY 3'),
  ('CompLab 3', 'COMPUTER LABORATORY 3'),
  ('COM LAB 3', 'COMPUTER LABORATORY 3')
on conflict (alias) do update set canonical_room = excluded.canonical_room;

-- ---------------------------------------------------------------------------
-- Family 2: "LR N" vs "RM N" — your real data shows this pair for
-- essentially every lecture-room number (101, 102, 104, 202, 203, 204,
-- 207, 302, 304, 305 confirmed as standalone entries under BOTH
-- prefixes; 201/301/303 confirmed for "RM" only via combined cells like
-- "RM 201 / RM 207" and "RM 301 / RM 305", but "LR 201/301/303" exist
-- standalone too — same pattern). This is systematic enough (essentially
-- every number, not a coincidental handful) that it reads as two
-- departments'/forms' naming conventions for the same physical rooms,
-- not a coincidence. Canonical form: "RM N" (higher usage counts across
-- the board suggest it's the more "official" convention). Also folds in
-- the bare-number ("102", "205", "304") and no-space ("LR202") variants.
-- ---------------------------------------------------------------------------

insert into public.room_aliases (alias, canonical_room)
values
  ('LR 101', 'RM 101'),
  ('LR 102', 'RM 102'),
  ('102', 'RM 102'),
  ('LR 104', 'RM 104'),
  ('LR 201', 'RM 201'),
  ('LR 202', 'RM 202'),
  ('LR202', 'RM 202'),
  ('LR 203', 'RM 203'),
  ('LR 204', 'RM 204'),
  ('LR 205', 'RM 205'),
  ('205', 'RM 205'),
  ('LR 207', 'RM 207'),
  ('LR 301', 'RM 301'),
  ('LR 302', 'RM 302'),
  ('LR 303', 'RM 303'),
  ('LR 304', 'RM 304'),
  ('304', 'RM 304'),
  ('LR 305', 'RM 305')
on conflict (alias) do update set canonical_room = excluded.canonical_room;

-- ---------------------------------------------------------------------------
-- NOT ALIASED — two different problems room_aliases can't solve:
--
-- 1. "6" (1 occurrence) — no matching pattern with anything else on the
--    list. Could be a truncated/mis-typed cell in the source file. Worth
--    tracking down manually rather than guessing.
--
-- 2. Every "X / Y" combined cell (AVR 1 / RM 203, RM 208 / RM 305, RM 204
--    / <blank>, etc. — roughly 35 distinct combinations in your data).
--    These aren't spelling variants of ONE room; the source file is
--    listing TWO possible rooms for one meeting (genuinely undecided at
--    the time the CFL was filled out, or a shared/rotating room). A
--    room_alias maps one spelling to one canonical name — it can't
--    "pick" between two real options. Fixing this means going back to
--    whoever filled out the file and asking which room actually got
--    used, then correcting the source data (or the committed meeting
--    row directly) — not something to paper over with an alias.
-- ---------------------------------------------------------------------------
