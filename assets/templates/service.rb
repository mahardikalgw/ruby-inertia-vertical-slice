module Domain
  # One transaction for the record, its children, its timeline row and its counter.
  # Side effects that can fail (mail, HTTP) run after the commit.
  class Create
    Result = Struct.new(:record, :errors, keyword_init: true) do
      def success? = record.present?
    end

    def initialize(workspace:, actor:, params:, files: [])
      @workspace = workspace
      @actor = actor
      @params = params
      @files = Array(files).compact
    end

    def call
      # A double submit from a real browser carries the same token, so it returns the
      # record that already exists instead of creating a second one.
      return Result.new(record: existing_record, errors: {}) if existing_record

      record = build_record
      return Result.new(record: nil, errors: record.errors.to_hash(true)) unless record.valid?

      persist(record)
    rescue ActiveRecord::RecordNotUnique
      # Two requests raced past the token lookup; the unique index is the last line of defence.
      retry_with_fresh_number(record)
    end

    private
      attr_reader :workspace, :actor, :params, :files

      def existing_record
        return if params[:form_token].blank?

        workspace.records.find_by(form_token: params[:form_token])
      end

      def build_record
        Record.new(
          workspace: workspace,
          owner: owner,
          created_by: actor,
          title: params[:title].to_s.strip,
          description: params[:description].to_s,
          status: "open",
          number: next_number,
          form_token: params[:form_token].presence
        )
      end

      def owner
        return actor unless actor.staff?

        workspace.users.find_by(id: params[:owner_id]) || actor
      end

      def persist(record)
        ActiveRecord::Base.transaction do
          record.save!
          files.each { |file| record.files.attach(file) }
          RecordEvent.record!(workspace: workspace, record: record, actor: actor, event_type: "created")
        end

        # After the commit: a mailer failure must not roll back the write.
        Domain::Notify.call(record: record, kind: "created", actor: actor)
        Result.new(record: record, errors: {})
      end

      def next_number
        # The counter is per workspace and per year, in the workspace's own timezone, so a ticket
        # created at 00:30 on 1 January in Jakarta is numbered for the new year.
        year = Time.current.in_time_zone(HelpdeskSetting.for(workspace).tz).year
        RecordCounter.next_number!(workspace: workspace, year: year, prefix: HelpdeskSetting.for(workspace).ticket_prefix)
      end

      def retry_with_fresh_number(record)
        raise if @retried

        @retried = true
        record.number = next_number
        persist(record)
      end
  end
end
