ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "turbo/broadcastable/test_helper"

module ActiveSupport
  class TestCase
    include Turbo::Broadcastable::TestHelper

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    def require_node_for_bridge_tests!
      skip "Node bridge tests intentionally skipped with SKIP_NODE_BRIDGE_TESTS=1" if ENV["SKIP_NODE_BRIDGE_TESTS"] == "1"

      assert system("node", "--version", out: File::NULL, err: File::NULL),
        "node is required for JavaScript bridge tests. Install Node, or set SKIP_NODE_BRIDGE_TESTS=1 for an intentional local opt-out."
    end

    def demo_run
      RuntimeAdapters::OpencodeDemo.start!(project_path: Rails.root.to_s)
    end

    def create_run(runtime_name: "opencode")
      Run.create!(
        runtime_name: runtime_name,
        project_path: Rails.root.to_s,
        mode: "demo",
        status: "running",
        started_at: Time.current
      )
    end

    def bridge_headers(run)
      { "X-Agent-Passports-Bridge-Token" => run.bridge_token }
    end

    def machine_bridge_headers
      { MachineBridge::HEADER => MachineBridge.token }
    end

    def create_passport(run:, actor_ref:, actor_name:, parent: nil, actor_kind: "agent", provider: "opencode", rules: {})
      defaults = { read: "allow", edit: "allow", bash: "allow", web: "allow", delegate: "allow" }
      rules = defaults.merge(rules)

      run.passports.create!(
        parent: parent,
        actor_ref: actor_ref,
        actor_name: actor_name,
        actor_kind: actor_kind,
        provider: provider,
        task: "Test actor",
        status: "active",
        read_rule: rules.fetch(:read),
        edit_rule: rules.fetch(:edit),
        bash_rule: rules.fetch(:bash),
        web_rule: rules.fetch(:web),
        delegate_rule: rules.fetch(:delegate)
      )
    end
  end
end
