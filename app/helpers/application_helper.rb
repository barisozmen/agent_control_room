module ApplicationHelper
  def passport_authority_summary(passport)
    counts = Passport::CAPABILITIES.each_with_object(Hash.new(0)) do |capability, tally|
      tally[passport.rule_for(capability)] += 1
    end

    return "full authority" if counts["allow"] == Passport::CAPABILITIES.size

    [ [ "ask", counts["ask"] ], [ "deny", counts["deny"] ] ].filter_map do |rule, count|
      "#{count} #{rule}" if count.positive?
    end.join(" / ")
  end

  def passport_authority_detail(passport)
    constrained = Passport::CAPABILITIES.filter_map do |capability|
      rule = passport.rule_for(capability)
      "#{capability}:#{rule}" unless rule == "allow"
    end

    constrained.any? ? constrained.join(" ") : "all capabilities allow"
  end

  def passport_authority_tone_classes(passport)
    rules = Passport::CAPABILITIES.map { |capability| passport.rule_for(capability) }

    if rules.include?("deny")
      "ap-tone-danger"
    elsif rules.include?("ask")
      "ap-tone-warning"
    else
      "ap-tone-neutral"
    end
  end

  def rule_badge_classes(rule)
    case rule
    when "allow" then "ap-rule ap-rule-allow"
    when "ask" then "ap-rule ap-rule-ask"
    else "ap-rule ap-rule-deny"
    end
  end

  def risk_badge_classes(risk)
    case risk
    when "low" then "ap-risk ap-risk-low"
    when "medium" then "ap-risk ap-risk-medium"
    else "ap-risk ap-risk-high"
    end
  end

  def result_text_classes(result)
    case result
    when "allowed", "running", "finished", "minted", "started", "completed" then "ap-result-positive"
    when "ask" then "ap-result-warning"
    when "denied", "blocked", "failed", "interrupted" then "ap-result-negative"
    else "ap-result-neutral"
    end
  end

  def status_dot_classes(status)
    case status
    when "running", "active" then "ap-status-active"
    when "starting", "asking", "pending" then "ap-status-pending"
    when "completed", "finished", "resolved", "allowed" then "ap-status-info"
    when "denied", "blocked", "failed", "interrupted" then "ap-status-danger"
    else "ap-status-muted"
    end
  end

  def status_label(status)
    status.to_s.humanize.downcase
  end

  def request_decision_button_classes(kind)
    case kind
    when :primary then "ap-decision-button ap-decision-primary"
    when :danger then "ap-decision-button ap-decision-danger"
    else "ap-decision-button ap-decision-secondary"
    end
  end

  def command_button_classes(kind = :secondary)
    kind == :primary ? "ap-command-button ap-command-primary" : "ap-command-button ap-command-secondary"
  end

  def tool_action_permission_state(action)
    request = action.permission_request
    passport = action.passport
    capability = action.capability
    rule = passport.rule_for(capability)

    if request.present?
      return pending_tool_permission_state(capability, rule) if request.status == "pending"

      return resolved_tool_permission_state(request, capability, rule)
    end

    if action.status == "blocked"
      return {
        label: "No permission",
        detail: "Passport rule #{capability}: deny blocked this action.",
        result: "denied"
      }
    end

    if observed_tool_action?(action)
      return {
        label: "Observed after execution",
        detail: "#{action.run.runtime_label} reported this action after it ran; Control Room did not gate it.",
        result: action.status
      }
    end

    if action.status.in?(%w[allowed running finished])
      if rule != "allow" && (grant = matching_passport_grant_for(action))
        return {
          label: "Allowed by passport grant",
          detail: "Grant matched: #{grant.capability} allow #{grant.pattern}.",
          result: "allowed"
        }
      end

      return {
        label: "Had passport permission",
        detail: "Passport rule #{capability}: #{rule} allowed this action.",
        result: "allowed"
      }
    end

    {
      label: "Recorded",
      detail: "Passport rule #{capability}: #{rule}.",
      result: action.status
    }
  end

  private

  def pending_tool_permission_state(capability, rule)
    {
      label: "Needs approval",
      detail: "Passport rule #{capability}: #{rule}; waiting for a user decision.",
      result: "ask"
    }
  end

  def resolved_tool_permission_state(request, capability, rule)
    case request.decision
    when "allow_once"
      {
        label: "Allowed once",
        detail: "Allowed for this action only; passport rule #{capability}: #{rule} stayed unchanged.",
        result: "allowed"
      }
    when "passport_grant"
      grant = request.grant
      pattern = grant&.pattern || request.suggested_grant_pattern
      {
        label: "Added to passport",
        detail: "Grant saved: #{capability} allow #{pattern}.",
        result: "allowed"
      }
    else
      {
        label: "Denied by user",
        detail: "Denied; no passport grant was created.",
        result: "denied"
      }
    end
  end

  def matching_passport_grant_for(action)
    action.passport.grants.detect do |grant|
      grant.capability == action.capability &&
        grant.effect == "allow" &&
        File.fnmatch?(grant.pattern, action.request_text.to_s, File::FNM_EXTGLOB)
    end
  end

  def observed_tool_action?(action)
    payload = action.canonical_payload || {}
    payload["type"] == "tool.observed" || payload["observation_mode"] == "posthoc"
  end
end
