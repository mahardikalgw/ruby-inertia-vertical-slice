# Props and the TypeScript contract

## The rule

Every prop the controller sends has exactly one TypeScript interface, and that interface lives in
`app/javascript/lib/types.ts`. The page imports it; it never declares an inline shape. If the
controller changes, the interface changes in the same commit — `npm run check` (`tsc`) is what makes
that non-negotiable.

```ruby
# controller
render inertia: "teams/index", props: {
  teams: @page.records.map { |team| Teams::Payload.summary(team) },
  pagination: @page.payload,
  filters: { q: params[:q].to_s }
}
```

```ts
// app/javascript/lib/types.ts
export interface TeamSummary {
  id: number
  name: string
  member_count: number
  status_label: string
}

export interface Pagination {
  page: number
  per_page: number
  total: number
  total_pages: number
}

export interface TeamsIndexProps {
  teams: TeamSummary[]
  pagination: Pagination
  filters: { q: string }
  meta: { page_title: string }
}
```

## Naming

- `snake_case` keys on both sides. Rails sends `ticket_number`; the interface says `ticket_number`.
  A casing transform would be a second source of truth for the wire format.
- Shared props keep their names: `auth`, `flash`, `errors`, `labels`, `nav`, `meta`,
  `empty_state`, `can`, `pagination`, `filters`. A page that reads `props.auth.user` works
  everywhere because every controller means the same thing by it.
- Booleans that grant capability live under `can` (`can.create`, `can.assign`), so a page never
  re-derives permission from `auth.user.role`. Roles change; `can` is the server's answer.

## What never travels as a prop

| Not a prop | Why | Instead |
|---|---|---|
| An ActiveRecord object | Leaks attributes and lazy relations; serialisation happens in the view layer | A hash from a payload builder |
| A relation | Serialised eagerly and unbounded | `relation.limit(n).map { ... }` |
| A status enum without a label | Forces the client to invent Indonesian text | `status` **and** `status_label` |
| A time as a `Time` object | Timezone and format become a client decision | ISO 8601 string (`iso8601`) |
| A URL built with `*_url` | Absolute host leaks into props | `*_path` |
| HTML | Injects a rendering decision into the payload | Structured data |

## Payload builders

`app/services/<domain>/payload.rb` (or `app/queries/<domain>/payload.rb` for read-only domains) is
the only place a hash is assembled.

```ruby
module Tickets
  class Payload
    def self.summary(ticket)
      {
        ticket_number: ticket.ticket_number,
        title: ticket.title,
        status: ticket.status,
        status_label: ticket.status_label,
        priority: ticket.priority,
        priority_label: ticket.priority_label,
        category_name: ticket.category.name,
        last_activity_at: iso(ticket.last_activity_at)
      }
    end

    def self.for_staff(ticket:, actor:)
      { ticket: summary(ticket), comments: all_comments(ticket), can: staff_can(ticket, actor) }
    end

    def self.for_requester(ticket:)
      { ticket: summary(ticket), comments: public_comments(ticket), can: { reply: true } }
    end

    def self.iso(time) = time&.iso8601
    private_class_method :iso
  end
end
```

### Why two builders instead of one with a flag

`for_requester` receives `public_comments(ticket)` — a relation that cannot contain an internal
note. There is no branch to forget, no `unless viewer.staff?` to get wrong, and a test can assert the
secret string is absent from the response even for an administrator-by-mistake. A single builder with
a visibility flag is one refactor away from leaking.

### The `mine` flag pattern

Anything the UI renders differently for "me" versus "them" is computed against the payload's
audience, on the server:

```ruby
def self.comment(comment, viewer:)
  {
    id: comment.id,
    body: comment.body,
    mine: comment.author_id == viewer.id,
    author_name: comment.author.name,
    visibility_label: comment.visibility_label
  }
end
```

The page then places a bubble by `mine` and never compares user ids — which it does not reliably have
for every audience.

## Dates, money, counts

- **Dates**: ISO 8601 strings. Formatting is a presentation concern (`Intl` on the client, or a
  `formatDate` helper), timezone is the server's (`in_time_zone(settings.tz)`).
- **Money**: integer minor units plus a currency code (`amount_cents`, `currency`). Never a float,
  never a pre-formatted string with a locale's separator baked in.
- **Counts**: integers, always the server's count. A client-side `tickets.filter(...).length` diverges
  from the paginated total as soon as pagination exists.
