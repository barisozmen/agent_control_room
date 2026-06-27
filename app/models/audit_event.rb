class AuditEvent < ApplicationRecord
  TIMELINE_PAGE_SIZE = 100
  TimelinePage = Struct.new(:events, :total_count, :older_count, :oldest_event_id, :before_id, keyword_init: true) do
    def more_events?
      older_count.positive?
    end

    def paginated?
      before_id.present?
    end
  end

  belongs_to :run
  belongs_to :passport, optional: true
  belongs_to :tool_action, optional: true
  belongs_to :permission_request, optional: true

  validates :event_kind, :result, :occurred_at, presence: true
  validates :source_event_id, uniqueness: { scope: :run_id, allow_nil: true }

  scope :chronological, -> { order(:occurred_at, :id) }
  scope :recent_for_timeline, ->(limit_count = TIMELINE_PAGE_SIZE) { reorder(occurred_at: :desc, id: :desc).limit(limit_count) }
  scope :before_timeline_event, lambda { |event|
    where(
      arel_table[:occurred_at].lt(event.occurred_at).or(
        arel_table[:occurred_at].eq(event.occurred_at).and(arel_table[:id].lt(event.id))
      )
    )
  }

  def self.timeline_page_for(run, before_id: nil, limit: TIMELINE_PAGE_SIZE)
    total_count = run.audit_events.count
    cursor = run.audit_events.find_by(id: before_id) if before_id.present?
    relation = cursor.present? ? run.audit_events.before_timeline_event(cursor) : run.audit_events
    newest_first = relation.recent_for_timeline(limit).to_a
    oldest_event = newest_first.last

    older_count =
      if oldest_event.blank?
        0
      elsif cursor.present?
        relation.before_timeline_event(oldest_event).count
      else
        total_count - newest_first.size
      end

    TimelinePage.new(
      events: newest_first.reverse,
      total_count: total_count,
      older_count: older_count,
      oldest_event_id: oldest_event&.id,
      before_id: cursor&.id
    )
  end
end
