defmodule BBRF.Favorites.CLITest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  import Plug.Test

  alias BBRF.{Favorites, Metatable}
  alias BBRF.API.Router
  alias BBRF.Favorites.CLI

  @first %{
    "stationuuid" => "abc-123",
    "url" => "http://example.com/stream",
    "name" => "Example FM",
    "countrycode" => "SE",
    "bitrate" => 128
  }
  @second %{@first | "stationuuid" => "def-456", "name" => "Other FM"}

  setup do
    Metatable.reset_db!()
    Favorites.add(@first)
    Favorites.add(@second)
    :ok
  end

  test "prints the favorites GET /favorites returns" do
    exported = capture_io(&CLI.export/0) |> Jason.decode!()

    assert exported == served_favorites()
    assert exported == [@first, @second]
  end

  defp served_favorites do
    conn(:get, "/favorites")
    |> Router.call(Router.init([]))
    |> Map.fetch!(:resp_body)
    |> Jason.decode!()
  end
end
