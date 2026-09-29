# Wedding Tracker

A private planning app for a couple: every cost, every gift, every guest and
every bed, on one page that lives on your phone's home screen.

**[Open the live demo →](https://aj-protzel.github.io/wedding-tracker/)** — a
made-up wedding, nothing to sign in to.

Built for a real 30-guest weekend wedding at a lodge, where the two of us, the
families and the vendors all needed the same numbers at the same time.

## What it does

**Costs**
- **The Numbers:** paid, still due, committed, money in, and what the wedding
  does to your account, all at a glance.
- **Money Out:** one row per vendor that opens to its payments and instalments
  (1/2, 2/2), with "due in 12 days" and "overdue" worked out from the dates. A
  refundable deposit is listed but kept out of every total.
- **Money In:** gifts, guest contributions and family money in one place. A
  gift in another currency shows its own amount beside its dollar value.
- **Family tab:** what a parent or grandparent promised against what they have
  actually given, so nobody has to keep it in their head. A promise to "cover
  the flowers" reads its figure straight from the florist's costs.

**Guests**
- Every guest as a name box that fills in as things get settled: grey, then a
  bed, then an RSVP, then paid in gold. Couples and families are tied together.
- Lodging drawn as cabin cards, bed by bed, each reading free, full or paid.
- Guest count, dinner count (vendors who eat included), RSVPs, who has paid
  and how much has been collected.

**Timeline and Notes**
- The weekend hour by hour, and an events table of what goes where.
- Numbers inside the text keep themselves current: "ceremony chairs: 28" is
  worked out from the guest list, never typed.
- Checklists (to plan, to buy, to rent, to book) that either of you can tick
  from your phone, and a box for dropping in a note to sort later.

## How it works

One HTML file, no build step, no framework. It signs in to your own
[Supabase](https://supabase.com) project and makes a single call that returns
everything the page draws. Every table is locked; the page can only read, tick
a checklist item or add a note, and only for someone you have given a login.
Hosting is any static host — Cloudflare Pages and GitHub Pages both work free.

## Set it up

1. Create a Supabase project. In the SQL editor, run `schema.sql`.
2. Under Authentication, turn sign-ups off and add a user for each of you,
   ticking Auto Confirm.
3. In `index.html`, set `SUPABASE_URL` and `SUPABASE_KEY` (Project Settings →
   API → the publishable key), and `HOME_CURRENCY` if not dollars.
4. Put the folder on a static host. On a phone, open it, then Share → Add to
   Home Screen, and sign in inside the new icon.

Fill in `settings` for your names, venue and date, then add vendors, guests,
beds and costs in the Supabase table editor — or ask an AI assistant with the
Supabase connector to do it for you. With the two keys left empty, the page
runs on `demo-data.json` instead.

## License

All rights reserved. The code is published to show the work; it may not be
copied, modified, hosted or sold without written permission. For a copy of
your own, get in touch.
