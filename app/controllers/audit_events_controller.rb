class AuditEventsController < ApplicationController
  def index
    @run = Run.find(params[:run_id])
    @audit_event_page = @run.audit_timeline_page(before_id: params[:before_id])

    if turbo_frame_request?
      render partial: "runs/audit_timeline", locals: { run: @run, audit_event_page: @audit_event_page }
    else
      redirect_to run_path(@run, panel: "audit")
    end
  end
end
