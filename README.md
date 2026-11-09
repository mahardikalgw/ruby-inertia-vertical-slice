# Inertia vertical slice

Add a feature to a Rails 8 + Inertia + React app as one vertical slice — route, skinny controller, query object for reads, service object for multi-step writes, typed server props, and an Inertia page inside a sanctioned layout. Use when asked to add a page, screen, action, endpoint, filter, or "make it possible to" do something in an Inertia monolith.

One skill, one repository. Part of a twelve-skill pack extracted from a production Rails 8 +
Inertia + React helpdesk monolith — the opinionated layer no public Rails or shadcn skill can know.
Version `2.0.0` tracks the source constitution.

## Install

```jsonc
// skills-lock.json
{
  "version": 1,
  "skills": {
    "inertia-vertical-slice": {
      "source": "mahardikalgw/inertia-vertical-slice",
      "sourceType": "github",
      "skillPath": "SKILL.md"
    }
  }
}
```

Or clone and symlink:

```bash
git clone git@github.com:mahardikalgw/inertia-vertical-slice.git
ln -s "$PWD/inertia-vertical-slice" .claude/skills/inertia-vertical-slice
```

## When to activate

- Adding a route, page, action, screen, list, filter, form, or detail view to an Inertia monolith.
- A controller action is growing past a screenful of code.
- A page needs data that is not already in props (the answer is never `fetch`).
- Reviewing a diff that touches `app/controllers`, `app/queries`, `app/services`, or `app/javascript/pages`.

## What's inside

```
inertia-vertical-slice/
  SKILL.md
  assets/templates/controller.rb
  assets/templates/page.tsx
  assets/templates/service.rb
  references/controller.md
  references/page.md
  references/props-and-types.md
  references/query-and-service.md
```

`SKILL.md` is a router (kept under 250 lines) — the depth lives in `references/`, and the
copy-in code lives in `assets/`.

## Validate

```bash
./bin/check-skill
```

Checks frontmatter, the activation section, link resolution, orphaned references, script
executability, leftover placeholders, and — when the source app is checked out next to this
repository — that vendored scripts still match it byte for byte. Runs in CI on every push.

## Related skills

- [`flat-ui-contract`](https://github.com/mahardikalgw/flat-ui-contract) — INV-1…INV-9 and THEME-1…3, with both gate scripts vendored
- [`scoped-authorization`](https://github.com/mahardikalgw/scoped-authorization) — scopes, 404-not-403, explicit public opt-outs, isolation by construction
- [`inertia-test-harness`](https://github.com/mahardikalgw/inertia-test-harness) — minitest + inertia helpers, builder objects, and system tests that do not flake

## Licence

MIT — see [LICENSE](LICENSE).
