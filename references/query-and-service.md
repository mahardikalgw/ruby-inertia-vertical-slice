# Query objects and service objects

The split is mechanical: **reads compose a relation, writes own a transaction.**

## Query objects (`app/queries/<domain>/`)

One class, one question. Constructor takes what scopes it, `relation` or `payload` returns the
answer. No `params` unless it is the pagination page — filters are extracted by the controller or a
`Filtered` object so the page's HTTP shape never leaks into the query.

```ruby
module Tickets
  class Filtered
    def initialize(relation, params)
      @relation = relation
      @params = params
    end

    def relation
      scope = @relation
      scope = scope.where(status: @params[:status]) if Ticket::STATUSES.include?(@params[:status].to_s)
      scope = scope.where(priority: @params[:priority]) if Ticket::PRIORITIES.include?(@params[:priority].to_s)
      scope = scope.where(support_team_id: @params[:team_id]) if @params[:team_id].present?
      scope
    end
  end
end
```

Rules that keep these composable:

- Return `ActiveRecord::Relation` whenever possible — the next object in the chain only knows how to
  narrow a relation.
- Validate the filter value against the model's own constant (`Ticket::STATUSES`), never by
  interpolating user input.
- Never call `.to_a`, `.count` or `.map` inside a scoper; that is the caller's or the payload's job.
- A scope that needs a payload hash (`counts`, `pagination`) exposes `payload` and memoises it.

### Pagination without a gem

```ruby
module Tickets
  class Page
    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 100

    def initialize(scope, params = {})
      @scope = scope
      @requested_page = [ params[:page].to_i, 1 ].max
      requested = params[:per_page].to_i
      @per_page = requested.positive? ? [ requested, MAX_PER_PAGE ].min : DEFAULT_PER_PAGE
    end

    def page = @page ||= [ @requested_page, total_pages ].min
    def records = @scope.limit(per_page).offset((page - 1) * per_page)
    def total = @total ||= @scope.unscope(:limit, :offset, :order).count
    def total_pages = [ (total.to_f / per_page).ceil, 1 ].max
    def payload = { page: page, per_page: per_page, total: total, total_pages: total_pages }
  end
end
```

Two details worth copying: `per_page` is clamped (a hand-edited URL cannot load a whole table), and
`page` is clamped into `1..total_pages` (a hand-edited page number lands on the last page instead of
an empty screen).

## Service objects (`app/services/<domain>/<verb>.rb`)

One public class method `.call`, one instance `#call`, one `Result`. The service is the only place a
multi-row write happens.

```ruby
module Tickets
  class Create
    Result = Struct.new(:ticket, :errors, keyword_init: true) do
      def success? = ticket.present?
    end

    def initialize(workspace:, actor:, params:, files: [])
      @workspace = workspace
      @actor = actor
      @params = params
      @files = Array(files).compact
    end

    def call
      ticket = build_ticket
      return Result.new(ticket: nil, errors: ticket.errors.to_hash(true)) unless ticket.valid?

      persist(ticket)
    rescue ActiveRecord::RecordNotUnique
      retry_with_fresh_number
    end

    private
      def persist(ticket)
        ActiveRecord::Base.transaction do
          ticket.save!
          @files.each { |file| ticket.files.attach(file) }
          TicketEvent.record!(workspace: @workspace, ticket: ticket, actor: @actor, event_type: "ticket_created")
        end

        Tickets::Notify.call(ticket: ticket, kind: "ticket_created", actor: @actor)
        Result.new(ticket: ticket, errors: {})
      end
  end
end
```

### The four rules

1. **Validate before the transaction.** `valid?` first, `save!` inside — a validation failure must
   not open a transaction that then rolls back a counter.
2. **One transaction for the record and its rows.** Record, children, timeline/event row. If any part
   is refused, nothing is half-applied.
3. **Side effects after the commit.** Mail, HTTP, push. A mailer that raises must not roll back a
   ticket that the user can no longer recreate.
4. **A typed error for a refusal.** `raise TransitionError, :reason_required` with a locale key per
   reason beats returning `errors: { base: ["not allowed"] }` — the controller, the mail, and the
   test can all assert the same symbol.

### Duplicate submits

A public form carries a `form_token` (a UUID rendered server-side). The service looks up an existing
row by that token first and returns it, so a double click or a browser retry returns the same record
instead of creating a second one. A unique index on the token column is the second line of defence
when two requests race.

### Authorization belongs outside the service, scoping belongs inside

The controller decides *who may call* (403). The service only receives records that were already
scoped (`Ticket.manageable_by(actor)`), and re-checks the edge it is about to cross. A service that
takes a raw id is a service that will eventually be called with someone else's record.
