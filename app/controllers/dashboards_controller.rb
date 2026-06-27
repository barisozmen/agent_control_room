class DashboardsController < ApplicationController
  before_action :sync_local_runtime_sessions, only: :show

  def show
    @run = Run.current
    @runs = Run.session_list
    @selected_passport = @run&.selected_passport(params[:passport_id])
    @panel = %w[passport audit].include?(params[:panel]) ? params[:panel] : nil

    render "runs/show" if @run.present?
  end

  private

  def sync_local_runtime_sessions
    return if Rails.env.test?

    ObservedRuntimeSessions::LocalProcessSyncer.sync_if_stale!
  end
end
