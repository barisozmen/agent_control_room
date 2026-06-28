require "test_helper"

class RuntimeAdapters::MultiRuntimeCliTest < ActiveSupport::TestCase
  FakeProcess = Struct.new(:spawn_args, :detached_pid) do
    def spawn(*args)
      self.spawn_args = args
      4242
    end

    def detach(pid)
      self.detached_pid = pid
    end
  end

  test "starts Claude Code with the shared bridge environment" do
    run = create_run(runtime_name: "claude_code")
    process = FakeProcess.new
    cli = RuntimeAdapters::ClaudeCodeCli.new(command: "claude-test", process: process, check_available: false)

    assert_equal 4242, cli.start_demo!(run: run)

    env = process.spawn_args.first
    options = process.spawn_args.last

    assert_equal "claude_code", env.fetch("AGENT_PASSPORTS_RUNTIME_NAME")
    assert_equal run.id.to_s, env.fetch("AGENT_PASSPORTS_RUN_ID")
    assert_equal run.bridge_token, env.fetch("AGENT_PASSPORTS_BRIDGE_TOKEN")
    assert_equal "claude-test", process.spawn_args[1]
    assert_equal "--print", process.spawn_args[2]
    assert_equal "stream-json", process.spawn_args[process.spawn_args.index("--output-format") + 1]
    assert_equal "Agent Identity Control Room demo", process.spawn_args[process.spawn_args.index("--name") + 1]
    assert_equal run.project_path, options.fetch(:chdir)
    assert_match %r{log/claude-code-demo-run-#{run.id}\.log\z}, options.fetch(:out)
    assert_equal [ :child, :out ], options.fetch(:err)
  end

  test "starts Codex with the shared bridge environment" do
    run = create_run(runtime_name: "codex")
    process = FakeProcess.new
    cli = RuntimeAdapters::CodexCli.new(command: "codex-test", process: process, check_available: false)

    assert_equal 4242, cli.start_demo!(run: run)

    env = process.spawn_args.first
    options = process.spawn_args.last

    assert_equal "codex", env.fetch("AGENT_PASSPORTS_RUNTIME_NAME")
    assert_equal run.id.to_s, env.fetch("AGENT_PASSPORTS_RUN_ID")
    assert_equal run.bridge_token, env.fetch("AGENT_PASSPORTS_BRIDGE_TOKEN")
    assert_equal "codex-test", process.spawn_args[1]
    assert_equal "never", process.spawn_args[process.spawn_args.index("--ask-for-approval") + 1]
    assert_equal "read-only", process.spawn_args[process.spawn_args.index("--sandbox") + 1]
    assert_equal "exec", process.spawn_args[process.spawn_args.index("exec")]
    assert_includes process.spawn_args, "--json"
    assert_equal run.project_path, options.fetch(:chdir)
    assert_match %r{log/codex-demo-run-#{run.id}\.log\z}, options.fetch(:out)
    assert_equal [ :child, :out ], options.fetch(:err)
  end
end
