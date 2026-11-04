defmodule BBRF.Role do
  @moduledoc """
  What this node does, from BBRF_ROLE (read in `config/runtime.exs`):

    * `all` (default) - api and ingester on one full database
    * `hub` - serves the api and the favorites; never ingests
    * `ingest` - runs the ingester and owns the full database; the api is
      optional

  BBRF_API and BBRF_INGESTER still switch a component off on top of the
  role.
  """

  @type t :: :hub | :ingest | :all

  @spec current() :: t()
  def current, do: Application.get_env(:bbrf, :role, :all)

  @doc "The components `role` runs, given the BBRF_API and BBRF_INGESTER switches."
  @spec components(t(), boolean(), boolean()) :: %{api: boolean(), ingester: boolean()}
  def components(:hub, api?, _ingester?), do: %{api: api?, ingester: false}

  def components(role, api?, ingester?) when role in [:ingest, :all],
    do: %{api: api?, ingester: ingester?}
end
