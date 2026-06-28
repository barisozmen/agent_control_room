class ToolActionsController < ApplicationController
  def index
    @run = Run.find(params[:run_id])
    @tool_action_page = @run.tool_action_page(before_id: params[:before_id])

    if turbo_frame_request?
      render partial: "runs/tool_action_list", locals: { run: @run, tool_action_page: @tool_action_page }
    else
      redirect_to run_path(@run, panel: "tools")
    end
  end
end
