# The page

## One layout, four choices

```
app/javascript/layouts/app-layout.tsx          signed-in product chrome (sidebar + top bar)
app/javascript/layouts/dashboard-layout.tsx    analytics/embed chrome
app/javascript/layouts/auth-layout.tsx         sign-in / single-panel centred card
app/javascript/layouts/marketing-layout.tsx    public pages with a marketing header
```

A page imports exactly one of them as its outermost element. No page renders `<nav>` or `<header>`
itself — the checker flags a second chrome implementation, because two chromes is how a product
starts to drift between screens.

```tsx
export default function TeamsIndex(props: TeamsIndexProps) {
  return (
    <AppLayout title="Tim" context={`${props.pagination.total} tim`} actions={<CreateButton />}>
      <Head title="Tim" />
      …
    </AppLayout>
  )
}
```

## Composition, not monolith

A page of 400 lines is the usual failure. The shape that survives:

```
pages/teams/index.tsx          the layout, the header, the composition
components/teams/team-row.tsx  one record
components/workspace/*.tsx     shared building blocks:
                               page-header, filter-bar, search-field, pagination, empty-state,
                               metric-card, result-count, status-badge, priority-badge, confirm-dialog
components/ui/*                shadcn primitives — the only place a raw element may exist
```

Before writing a component, check `components/workspace/` — a filter bar, empty state, pagination,
badge and confirm dialog already exist, and re-inventing one is how the product ends up with three
slightly different empty states.

## Presentation state only

```tsx
const [open, setOpen] = useState(false)                    // fine
const [draft, setDraft] = useState(filters.q)              // fine
const [tickets, setTickets] = useState(props.tickets)      // NOT fine
```

Filtering, sorting, paging and any record change are a navigation: build the query string and call
`router.get` so the server re-renders with new props. `useState` holds the draft while the user types
and nothing else.

```tsx
function submit(next: Partial<Filters>) {
  const params = new URLSearchParams({ ...filters, ...next })
  router.get('/teams', Object.fromEntries(params), { preserveState: true, preserveScroll: true })
}
```

`preserveState` keeps the input focused; `preserveScroll` keeps the table where it was.

## Forms

Inertia's `useForm` is the shape:

```tsx
const form = useForm({ name: '', description: '' })

<form onSubmit={(event) => { event.preventDefault(); form.post('/teams') }}>
  <Field label="Nama" error={form.errors.name}>
    <Input value={form.data.name} onChange={(e) => form.setData('name', e.target.value)} />
  </Field>
  <Button type="submit" disabled={form.processing}>Simpan</Button>
</form>
```

Server validation errors arrive in `form.errors` under the same key the model used. Do not duplicate
the validation on the client: `required` is a convenience, not a rule.

## Empty, loading and error states

- **Empty**: always rendered. A list with no rows shows a sentence explaining what would appear and,
  when the viewer may create one, the action. Props carry `empty_state.title`, `.body`,
  `.action_label`, `.action_href` from the server.
- **Loading**: Inertia navigation is server round-trip; a skeleton is only warranted for a region
  that stays mounted across navigations.
- **Error**: 403/404/422/500 render one shared page (`pages/errors/show.tsx`). A page does not build
  its own error screen, and does not catch a server refusal to display a friendlier message — the
  refusal already says what happened.

## Accessibility minimum

- Every interactive element is a component from `components/ui` (a raw `<button>` fails the checker).
- A focus ring must stay visible; `outline-none` is forbidden outside the documented text-field
  exemption.
- Icon-only controls carry `aria-label`; the visual tooltip is not the label.
- A table header uses `<TableHead>`; numeric columns use the recipe's `numeric` class so figures stay
  tabular and aligned.

## Indonesian copy

Requester-facing strings live in `app/javascript/lib/copy.id.ts` (client chrome) and
`config/locales/helpdesk.id.yml` (server-owned text). A JSX string literal in Indonesian that is also
needed by a mailer or a CSV is a bug waiting to diverge — put it in the locale file and send it as a
prop. See `indonesian-product-copy`.
