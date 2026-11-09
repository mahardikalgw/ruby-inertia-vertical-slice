// Skeleton for a read-and-write resource controller in an Inertia monolith.
// Replace Record/Domain with the real nouns. Nothing here may grow past ~10 lines per action.
class RecordsController < ApplicationController
  before_action :find_visible_record!, only: :show
  before_action :authorize_reader!, only: :index
  before_action :prevent_caching

  # GET /records
  def index
    records = Domain::VisibleTo.new(Current.user).relation
    @page = Domain::Page.new(records, params)
    can_create = Current.user.can_create_records?

    render inertia: "records/index", props: {
      records: @page.records.map { |record| Domain::Payload.summary(record) },
      pagination: @page.payload,
      filters: { q: params[:q].to_s, status: params[:status].presence },
      empty_state: {
        title: I18n.t("domain.records.empty_title"),
        body: I18n.t("domain.records.empty_body"),
        action_label: (I18n.t("domain.records.create") if can_create),
        action_href: ("/records/new" if can_create)
      },
      can: { create: can_create },
      meta: { page_title: I18n.t("domain.nav.records") }
    }
  end

  # GET /records/new
  def new
    render inertia: "records/new", props: { options: Domain::FormOptions.new(current_workspace).options }
  end

  # POST /records
  def create
    result = Domain::Create.new(
      workspace: current_workspace, actor: Current.user, params: record_params, files: params[:files]
    ).call

    if result.success?
      redirect_to record_path(result.record), status: :see_other, notice: I18n.t("domain.records.created")
    else
      redirect_to new_record_path, inertia: { errors: result.errors }
    end
  end

  # GET /records/:id
  def show
    props = if Current.user.staff?
              Domain::Payload.for_staff(record: @record, actor: Current.user)
            else
              Domain::Payload.for_requester(record: @record)
            end

    render inertia: "records/show", props: props
  end

  private
    # Scoped lookup: a foreign id raises RecordNotFound, which the shared handler renders as 404.
    def find_visible_record!
      @record = Domain::VisibleTo.new(Current.user).relation.find_by!(number: params[:id])
    end

    def authorize_reader!
      deny! unless Current.user.can_read_records?
    end

    def record_params
      params.permit(:title, :description, :status, :form_token)
    end

    def prevent_caching
      response.headers["Cache-Control"] = "no-store"
    end
end
