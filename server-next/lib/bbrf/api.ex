defmodule BBRF.API do
  @moduledoc """
  The HTTP component: serves the bbrf frontend bundle and the JSON API it
  calls (`BBRF.API.Router`) on PORT, with the same paths and response
  shapes as the node server, so the frontend does not change.
  """

  alias BBRF.Env

  def port, do: Env.int("PORT", 4881)

  def children do
    [{Bandit, plug: BBRF.API.Router, scheme: :http, ip: {0, 0, 0, 0}, port: port()}]
  end

  def describe, do: "api on port #{port()}"
end
