<!--
Thanks for the PR. A few quick things to keep this moving:

- Keep the PR focused. One concern per PR is much easier to review than a
  grab-bag.
- If this fixes an open issue, write `Closes #123` somewhere in the body.
- For non-trivial work, please discuss in an issue first.
-->

## What

<!-- One-paragraph summary of the change. -->

## Why

<!-- The user-facing problem this solves, or the cleanup motivation. -->

## How

<!-- How the change works. Skip this if "What" already explains it. -->

## How to test

<!-- Steps a reviewer can follow on their machine to confirm this works. -->

## Checklist

- [ ] I read [`CONTRIBUTING.md`](../CONTRIBUTING.md).
- [ ] I ran `npm run lint` and `npm run build`.
- [ ] If I changed `complete-schema.sql`, I also added a migration under
      `supabase/migrations/` (and vice versa).
- [ ] If I added a new env var, I updated `.env.example` and
      `.env.selfhosted.example`.
- [ ] Docs updated where relevant.
