defmodule RadioAnalyzer.Repo do
  use Ecto.Repo,
    otp_app: :radio_analyzer,
    adapter: Ecto.Adapters.SQLite3
end
