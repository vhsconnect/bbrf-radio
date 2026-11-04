defmodule BBRF.EnvTest do
  use ExUnit.Case, async: false

  alias BBRF.Env

  @var "BBRF_TEST_FLAG"

  setup do
    on_exit(fn -> System.delete_env(@var) end)
    System.delete_env(@var)
    :ok
  end

  test "int falls back to the default for missing or garbage values" do
    assert Env.int("DEFINITELY_NOT_SET_#{:erlang.unique_integer()}", 7) == 7

    System.put_env(@var, "nope")
    assert Env.int(@var, 7) == 7
  end

  test "unset uses the default" do
    assert Env.flag(@var, true) == true
    assert Env.flag(@var, false) == false
  end

  test "1 is on and 0 is off, whatever the default" do
    System.put_env(@var, "1")
    assert Env.flag(@var, false) == true

    System.put_env(@var, "0")
    assert Env.flag(@var, true) == false
  end

  test "any other value raises" do
    System.put_env(@var, "yes")

    assert_raise ArgumentError, ~r/must be 1 or 0/, fn -> Env.flag(@var, true) end
  end
end
