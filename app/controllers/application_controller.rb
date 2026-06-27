class ApplicationController < ActionController::Base
  BridgeUnauthorized = Class.new(StandardError)

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from BridgeUnauthorized, with: :render_bridge_unauthorized

  private

  def authenticate_bridge_token!(run)
    token = request.headers["X-Agent-Passports-Bridge-Token"].presence || params[:bridge_token].presence
    valid = token.present? &&
      run.bridge_token.present? &&
      token.bytesize == run.bridge_token.bytesize &&
      ActiveSupport::SecurityUtils.secure_compare(token, run.bridge_token)

    raise BridgeUnauthorized, "Invalid bridge token" unless valid
  end

  def authenticate_bridge_or_machine_token!(run)
    return if valid_run_bridge_token?(run)
    return if valid_machine_token?

    raise BridgeUnauthorized, "Invalid bridge token"
  end

  def authenticate_machine_token!
    raise BridgeUnauthorized, "Invalid machine token" unless valid_machine_token?
  end

  def render_bridge_unauthorized(error)
    render json: { ok: false, error: error.message }, status: :unauthorized
  end

  def render_flash_stream(kind, message, status: :unprocessable_entity)
    flash.now[kind] = message
    render turbo_stream: turbo_stream.replace("flash_messages", partial: "layouts/flash"), status: status
  end

  def valid_run_bridge_token?(run)
    token = request.headers["X-Agent-Passports-Bridge-Token"].presence || params[:bridge_token].presence
    token.present? &&
      run.bridge_token.present? &&
      token.bytesize == run.bridge_token.bytesize &&
      ActiveSupport::SecurityUtils.secure_compare(token, run.bridge_token)
  end

  def valid_machine_token?
    token = request.headers[MachineBridge::HEADER].presence || params[:machine_token].presence
    MachineBridge.valid_token?(token)
  end
end
