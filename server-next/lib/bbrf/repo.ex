defmodule BBRF.Repo do
  use Ecto.Repo,
    otp_app: :bbrf,
    adapter: Ecto.Adapters.SQLite3
end
