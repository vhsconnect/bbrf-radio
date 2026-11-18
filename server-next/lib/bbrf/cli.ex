defmodule BBRF.CLI do
  @moduledoc """
  Boot for the one-off commands (`BBRF.Metrics.CLI`, `BBRF.Favorites.CLI`):
  starts the Repo on the configured database (BBRF_DB) with neither the
  API nor the ingester, and never migrates.
  """

  alias BBRF.Repo

  def start_repo do
    :ok = loaded(Application.load(:bbrf))
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = Repo.start_link(pool_size: 1, log: false)
    :ok
  end

  def database, do: Application.get_env(:bbrf, Repo, [])[:database]

  def pending_migrations do
    for {:down, version, _name} <- Ecto.Migrator.migrations(Repo), do: version
  end

  defp loaded(:ok), do: :ok
  defp loaded({:error, {:already_loaded, :bbrf}}), do: :ok
end
