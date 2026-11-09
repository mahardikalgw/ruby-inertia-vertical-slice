---
name: inertia-vertical-slice
description: Add a feature to a Rails 8 + Inertia + React app as one vertical slice — route, skinny controller, query object for reads, service object for multi-step writes, typed server props, and an Inertia page inside a sanctioned layout. Use when asked to add a page, screen, action, endpoint, filter, or "make it possible to" do something in an Inertia monolith.
version: 2.0.0
---

# Inertia vertical slice

One request path. The controller renders an Inertia page with props the server built; the page
renders and nothing else. Everything below exists so a new feature lands as a slice rather than as
a screen with a private API behind it.

## When to activate

- Adding a route, page, action, screen, list, filter, form, or detail view to an Inertia monolith.
- A controller action is growing past a screenful of code.
- A page needs data that is not already in props (the answer is never `fetch`).
- Reviewing a diff that touches `app/controllers`, `app/queries`, `app/services`, or `app/javascript/pages`.

Do not activate for styling-only changes (use `flat-ui-contract`) or for test authoring alone (use
`inertia-test-harness`).

## The loop

### 1. Write the contract first

Before code: the HTTP route, the Inertia component name, and the prop shape. One line each. If you
cannot write the prop shape, the requirement is not understood yet.

```
GET /teams            -> teams/index   { teams: Team[], pagination: {...}, filters: {...}, can: {...} }
```

Props are `snake_case` and mirror a TypeScript interface added to `app/javascript/lib/types.ts`.
There is no JSON endpoint and no client-side fetch of primary data — if the page needs it, the
server sends it.

### 2. Route

```ruby
resources :teams, only: %i[ index show ]   # address records by their human number when they have one
```

Anything nested under a namespace stays inside that namespace's controller directory. Never add a
`/api` namespace; it is the beginning of the second request path this architecture forbids.

### 3. Read side — a query object

`app/queries/<domain>/<name>.rb`. One class, one question, returns a relation or a payload hash.
Authorization belongs here, not in the controller:

```ruby
class Teams::VisibleTo
  def initialize(user) = @user = user
  def relation
    scope = Team.where(workspace_id: @user.workspace_id)
    @user.admin? ? scope : scope.where(id: @user.support_team_ids)
  end
end
```

Pagination, filtering and counting are also query objects (`Tickets::Page`, `Tickets::Filtered`,
`Tickets::Counts`). No gems for either; offset pagination is twenty lines.

### 4. Write side — a service object

`app/services/<domain>/<verb>.rb`. A `Result` struct with `success?`, one `ActiveRecord` transaction
covering the record plus its side effects, and a typed error when the operation is refused.

```ruby
result = Teams::Create.new(workspace: current_workspace, actor: Current.user, params: team_params).call
if result.success?
  redirect_to team_path(result.team), status: :see_other
else
  redirect_to new_team_path, inertia: { errors: result.errors }
end
```

Side effects that can fail (mail, HTTP) run *after* the commit, never inside it.

### 5. Controller — authorization, params, one call, render

```ruby
class TeamsController < ApplicationController
  before_action :find_visible_team!, only: :show

  def index
    teams = Teams::VisibleTo.new(Current.user).relation
    @page = Teams::Page.new(teams, params)

    render inertia: "teams/index", props: {
      teams: @page.records.map { |team| Teams::Payload.summary(team) },
      pagination: @page.payload,
      filters: { q: params[:q].to_s },
      meta: { page_title: I18n.t("helpdesk.nav.teams") }
    }
  end

  private
    def team_params = params.permit(:name, :description)
end
```

Rules the reviewer will check: no ActiveRecord in the action body, no business rule, no conditional
that belongs to a policy or a service, and roughly ten lines per action. A refusal uses the shared
`deny!` (403) — see `scoped-authorization`.

### 6. Payload builder — one serialiser per audience

Props are built by a payload object, never by `as_json` on a model:

```ruby
module Teams
  class Payload
    def self.summary(team)
      {
        id: team.id,
        name: team.name,
        member_count: team.memberships.size,
        status_label: team.status_label   # human label from the server
      }
    end
  end
end
```

Two audiences means two builders (`for_staff`, `for_requester`) so a field that must not leak is
absent by construction rather than filtered by a flag. Labels come from the server; the client never
maps a status enum to text.

### 7. Page — a layout, a `Head`, and presentation state

```tsx
import { Head } from '@inertiajs/react'
import AppLayout from '@/layouts/app-layout'
import { EmptyState } from '@/components/workspace/empty-state'
import type { TeamsIndexProps } from '@/lib/types'

export default function TeamsIndex({ teams }: TeamsIndexProps) {
  return (
    <AppLayout title="Tim">
      <Head title="Tim" />
      {teams.length === 0 ? <EmptyState title="Belum ada tim" body="Tim pendukung belum dibuat." /> : null}
    </AppLayout>
  )
}
```

## Prohibitions

| Never | Because |
|---|---|
| A JSON API route (`/api/*`) for the same feature | One request path, one validation surface, one authorization boundary |
| `useEffect` + `fetch` for primary content | The server already had this data one request ago |
| An ActiveRecord query in a controller or a prop block | Untestable without a request cycle; the next caller copies it |
| Business logic in a React component | It cannot be tested without a browser and cannot be reused by mail or CSV |
| A new top-level `app/` directory | The directory contract is fixed: `models controllers views services queries jobs mailers helpers` |
| `as_json` / `to_json` as the prop builder | Leaks every column by default, including the ones that must never reach a requester |
| A status→label map on the client | Two sources of truth for a workflow that lives in the database |
| Editing a page to add chrome | Four layouts only; a second nav is a defect, not a feature |

## Done when

1. `bin/rails test` passes and a test exists for the new route (happy path **and** authentication).
2. `npm run check` passes — the prop interface in `types.ts` matches what the controller sends.
3. `bin/check-ui-components` and `bin/check-theme` pass (page is inside a sanctioned layout, no raw
   `<button>`, no forbidden utility).
4. Every action is ≤ ~10 lines, and every ActiveRecord call sits in a query or service object.
5. No endpoint returns JSON for the page's own content.

## References

- [references/controller.md](references/controller.md) — action shapes, `before_action`, refusal, flash, caching
- [references/query-and-service.md](references/query-and-service.md) — query objects, service objects, `Result`, transactions
- [references/props-and-types.md](references/props-and-types.md) — prop naming, payload builders, the `types.ts` contract
- [references/page.md](references/page.md) — layouts, composition, presentation state, empty and error states
- [assets/templates/controller.rb](assets/templates/controller.rb) — controller skeleton to copy
- [assets/templates/service.rb](assets/templates/service.rb) — service object skeleton with `Result`
- [assets/templates/page.tsx](assets/templates/page.tsx) — page skeleton inside `app-layout`


