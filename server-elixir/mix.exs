defmodule RadioAnalyzer.MixProject do
  use Mix.Project

  def project do
    [
      app: :radio_analyzer,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # the application is a long-running node: collectors, plus the HTTP server
  # for the bbrf frontend; run it with `mix run --no-halt`
  def application do
    [
      extra_applications: [:logger],
      mod: {RadioAnalyzer.Application, []}
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
      # JSON API and static bundle for the bbrf frontend, on the collectors' node
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"}
    ]
  end
end
