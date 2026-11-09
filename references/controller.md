# Controller shapes

## The default action

```ruby
def index
  records = Domain::VisibleTo.new(Current.user).relation
  @page = Domain::Page.new(records, params)

  render inertia: "domain/index", props: {
    records: @page.records.map { |record| Domain::Payload.summary(record) },
    pagination: @page.payload,
    filters: { q: params[:q].to_s, status: params[:status].presence },
    empty_state: { title: I18n.t("domain.empty_title"), body: I18n.t("domain.empty_body") },
    can: { create: Current.user.can_create_records? },
    meta: { page_title: I18n.t("domain.nav.index") }
  }
end
```

Five blocks and no more: the collection, its pagination, the echoed filters, the copy for the empty
state, and the permissions the page may use. Anything else is a second controller call away.

## Writes: one domain call, then a branch

```ruby
def create
  result = Domain::Create.new(workspace: current_workspace, actor: Current.user, params: record_params).call

  if result.success?
    redirect_to record_path(result.record), status: :see_other,
                notice: I18n.t("domain.created")
  else
    redirect_to new_record_path, inertia: { errors: result.errors }
  end
end
```

`status: :see_other` on every redirect after a write. The browser then GETs the result instead of
re-posting it, which is what makes refresh safe.

Validation errors travel as Inertia `errors`, not as a rendered body: the form reads them from
`usePage().props.errors` and the page keeps its state.

## `before_action` order

Authorization, then lookup, then caching:

```ruby
class RecordsController < ApplicationController
  before_action :find_visible_record!, only: :show      # scoping already refuses foreign rows with 404
  before_action :authorize_reader!, only: :index        # role check -> deny! -> 403
  before_action :prevent_caching, only: :show
```

- Lookups go through the scope, never through `Model.find`. A foreign id then raises
  `RecordNotFound` and the shared `rescue_from` renders 404 — existence is never confirmed.
- A role refusal calls `deny!` and the shared handler renders 403.
- Browser-back onto a signed-in page must not show a stale queue, so any per-user page sets
  `Cache-Control: no-store`.

## Shared props come from `ApplicationController`

Do not re-send auth, flash, nav or label maps from a feature controller. They are already shared:

```ruby
inertia_share do
  {
    auth: { user: current_user_payload, workspace: current_workspace_payload },
    flash: { notice: flash[:notice], alert: flash[:alert] },
    labels: { status: status_labels, priority: priority_labels },
    nav: nav_payload
  }
end
```

A page that needs a label reads `props.labels.status["open"]`. That is why no controller sends the
word "Open" itself.

## Rendering a page

- Component name is a path relative to `app/javascript/pages`, no extension: `"tickets/show"`.
- Props are a plain Ruby hash of scalars, arrays and hashes — no ActiveRecord objects, no models
  with `as_json`, no lazy relations.
- Every page sends `meta: { page_title: ... }`; the layout reads it for the document title.
- `empty_state` travels from the server so the Indonesian copy lives in a locale file, not in JSX.

## Things that never appear in a controller

```ruby
# no
@tickets = Ticket.where(status: params[:status]).where(workspace: current_workspace).order(created_at: :desc)
Ticket.find(params[:id])
ticket.update!(status: "closed") if Current.user.supervisor?
render json: { tickets: @tickets }
```

Each line is either a query object, a scoped lookup, a service call, or a forbidden second API. The
controller is the place where a request becomes a page, nothing else.
