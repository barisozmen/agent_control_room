require "test_helper"

class InternalIndexingTest < ActionDispatch::IntegrationTest
  test "control room pages emit noindex directives" do
    get root_path

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "meta[name='robots'][content='noindex, nofollow']"
  end

  test "turbo frame responses emit noindex header" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "auth-reviewer", actor_name: "auth-reviewer", parent: owner)

    get run_passport_path(run, passport), headers: { "Turbo-Frame" => "passport_detail" }

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  test "robots txt disallows all crawlers" do
    get "/robots.txt"

    assert_response :success
    assert_includes response.body, "User-agent: *"
    assert_includes response.body, "Disallow: /"
  end
end
