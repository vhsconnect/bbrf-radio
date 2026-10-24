defmodule BBRF.RoleTest do
  use ExUnit.Case, async: true

  alias BBRF.Role

  test "all and ingest run the components their switches leave on" do
    for role <- [:all, :ingest] do
      assert Role.components(role, true, true) == %{api: true, ingester: true}
      assert Role.components(role, false, true) == %{api: false, ingester: true}
      assert Role.components(role, true, false) == %{api: true, ingester: false}
    end
  end

  test "a hub never ingests, whatever the switch says" do
    assert Role.components(:hub, true, true) == %{api: true, ingester: false}
    assert Role.components(:hub, false, true) == %{api: false, ingester: false}
  end

  test "defaults to all" do
    assert Role.current() == :all
  end
end
