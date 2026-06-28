class Passport < ApplicationRecord
  ACTOR_KINDS = %w[human agent].freeze
  PROVIDERS = %w[local opencode claude_code codex].freeze
  RULES = %w[deny ask allow].freeze
  CAPABILITIES = %w[read edit bash web delegate].freeze
  RULE_RANK = { "deny" => 0, "ask" => 1, "allow" => 2 }.freeze

  belongs_to :run, counter_cache: true
  belongs_to :parent, class_name: "Passport", optional: true

  has_many :children, -> { order(:created_at, :id) }, class_name: "Passport", foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy
  has_many :tool_actions, dependent: :destroy
  has_many :permission_requests, dependent: :destroy
  has_many :grants, dependent: :destroy
  has_many :audit_events, dependent: :nullify

  validates :actor_ref, :actor_name, :actor_kind, :provider, :status, presence: true
  validates :actor_ref, uniqueness: { scope: :run_id }
  validates :actor_kind, inclusion: { in: ACTOR_KINDS }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :read_rule, :edit_rule, :bash_rule, :web_rule, :delegate_rule, inclusion: { in: RULES }
  validate :agent_has_parent
  validate :child_rules_do_not_exceed_parent

  def root?
    parent_id.nil?
  end

  def agent?
    actor_kind == "agent"
  end

  def rule_for(capability)
    public_send("#{capability}_rule")
  end

  def lineage
    root? ? [ self ] : parent.lineage + [ self ]
  end

  def lineage_label
    lineage.map(&:actor_name).join(" / ")
  end

  def capability_rows(local_grants = ordered_grants)
    grants_by_capability = local_grants.group_by(&:capability)

    CAPABILITIES.map do |capability|
      {
        capability: capability,
        rule: rule_for(capability),
        parent_rule: parent&.rule_for(capability),
        grants: grants_by_capability.fetch(capability, [])
      }
    end
  end

  def ordered_grants
    grant_records =
      if association(:grants).loaded?
        grants.to_a
      else
        grants.order(:capability, :pattern, :id).to_a
      end

    grant_records.sort_by { |grant| [ grant.capability.to_s, grant.pattern.to_s, grant.id.to_i ] }
  end

  def local_grant_for?(capability, action_text)
    grants.where(capability: capability, effect: "allow").any? do |grant|
      File.fnmatch?(grant.pattern, action_text.to_s, File::FNM_EXTGLOB)
    end
  end

  def authorization_for(capability, action_text)
    return "allow" if local_grant_for?(capability, action_text)

    rule_for(capability)
  end

  private

  def agent_has_parent
    errors.add(:parent, "must exist for agent passports") if agent? && parent.blank?
  end

  def child_rules_do_not_exceed_parent
    return if parent.blank?

    CAPABILITIES.each do |capability|
      next if RULE_RANK.fetch(rule_for(capability)) <= RULE_RANK.fetch(parent.rule_for(capability))

      errors.add("#{capability}_rule", "cannot exceed parent passport")
    end
  end
end
