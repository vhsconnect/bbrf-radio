defmodule BBRF do
  @moduledoc """
  The bbrf server: one OTP app with two components that share the
  SQLite database and the code in `BBRF.*`:

    * `BBRF.API` - the frontend bundle and the JSON API it calls
    * `BBRF.Ingester` - keeps the station catalogue and what each station
      plays up to date

  `BBRF.Application` starts either or both.
  """
end
