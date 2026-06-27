class PermissionDecisionsController < ApplicationController
  def create
    @permission_request = PermissionRequest.find(params[:permission_request_id])
    @permission_request.resolve!(decision_params.fetch(:scope))
    @run = @permission_request.run
    complete_run_if_all_requests_resolved
    @passport = @permission_request.passport
    @run.broadcast_control_room!(selected_passport: @passport)

    respond_to do |format|
      format.html { redirect_to run_path(@run, passport_id: @passport.id) }
      format.json { render json: @permission_request.bridge_payload }
      format.turbo_stream
    end
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    respond_to do |format|
      format.html { redirect_to run_path(@permission_request.run), alert: error.message }
      format.json { render json: { ok: false, error: error.message }, status: :unprocessable_entity }
      format.turbo_stream { render_flash_stream(:alert, error.message) }
    end
  end

  private

  def decision_params
    params.expect(decision: [:scope])
  end

  def complete_run_if_all_requests_resolved
    return if @run.permission_requests.where(status: "pending").exists?
    return unless @run.status == "running"

    @run.update!(status: "completed", finished_at: Time.current)
    AuditEvent.create!(
      run: @run,
      event_kind: "session.finished",
      result: "completed",
      action_summary: "#{@run.runtime_label} demo completed after all permission requests resolved",
      occurred_at: Time.current
    )
  end

end
