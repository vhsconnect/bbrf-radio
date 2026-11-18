defmodule BBRF.Favorites.CLI do
  @moduledoc """
  Prints the favorites to stdout as JSON, in the shape `GET /favorites`
  returns, from the configured database (BBRF_DB):

      bin/bbrf eval "BBRF.Favorites.CLI.main()"
      mix run --no-compile --no-start -e "BBRF.Favorites.CLI.main()"

  Compile first under `mix`: compile output goes to stdout too.
  """

  alias BBRF.{CLI, Favorites}

  def main do
    :ok = CLI.start_repo()
    export()
  end

  def export, do: IO.puts(Jason.encode!(Favorites.list(), pretty: true))
end
