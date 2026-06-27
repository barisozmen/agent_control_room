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
    when "allowed", "finished", "minted", "started", "completed" then "ap-result-positive"
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
end
