defmodule BBRF.MixProject do
  use Mix.Project

  def project do
    [
      app: :bbrf,
      version: "0.11.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # the application is a long-running node running the api, the ingester or
  # both (see BBRF.Application); run it with `mix run --no-halt`
  def application do
    [
      extra_applications: [:logger, :observer],
      mod: {BBRF.Application, []}
    ]
  end

  defp deps do
    [
      # models + migrations on top of SQLite (exqlite NIF, bundled sqlite3)
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.18"},
      # HTTP client for radio-browser + icecast status pages (Finch-based)
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      # JSON API and static bundle for the bbrf frontend
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"}
    ]
  end
end
