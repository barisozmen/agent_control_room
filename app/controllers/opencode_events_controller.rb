class OpencodeEventsController < ApplicationController
  UnsupportedBridgeMediaType = Class.new(StandardError)

  skip_forgery_protection only: :create

  def create
    require_json_bridge_request!
    authenticate_machine_token!

    ingestion = ObservedOpencodeSessions::Ingestor.new(event: opencode_event_params).process
    ingestion.run.broadcast_runtime_event!(
      audit_event: ingestion.audit_event,
      ui_changes: ingestion.ui_changes,
      selected_passport: selected_passport_for(ingestion.result)
    )

    render json: opencode_event_response(ingestion), status: :created
  rescue UnsupportedBridgeMediaType => error
    render json: { ok: false, error: error.message }, status: :unsupported_media_type
  rescue ActiveRecord::RecordNotFound, KeyError, ArgumentError, ActiveRecord::RecordInvalid => error
    render json: { ok: false, error: error.message }, status: :unprocessable_entity
  end

  private

  def require_json_bridge_request!
    return if request.media_type == "application/json"

    raise UnsupportedBridgeMediaType, "OpenCode observer events must be posted as JSON"
  end

  def opencode_event_params
    payload = params[:opencode_event].presence || params[:runtime_event].presence || params
    payload.to_unsafe_h.except("controller", "action").with_indifferent_access
  end

  def opencode_event_response(ingestion)
    result = ingestion.result
    response = {
      ok: true,
      run_id: ingestion.run.id,
      run_url: run_url(ingestion.run),
      id: result.id,
      type: result.class.name
    }
    response[:status] = result.status if result.respond_to?(:status)
    if result.respond_to?(:permission_request) && result.permission_request.present?
      response[:permission_request_id] = result.permission_request.id
      response[:permission_request_url] = permission_request_url(result.permission_request)
    end
    response
  end

  def selected_passport_for(result)
    return result if result.is_a?(Passport)
    return result.passport if result.respond_to?(:passport)
  end
end
