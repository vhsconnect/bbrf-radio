defmodule BBRF.Application do
  @moduledoc """
  Starts the shared database (`BBRF.Repo`, then `BBRF.Setup` for pragmas
  and migrations), then the components the node's `BBRF.Role` runs and
  the switches leave on:

    * `BBRF.API` - BBRF_API (default 1)
    * `BBRF.Ingester` - BBRF_INGESTER (default 1), never on a hub
    * `BBRF.Sync` - from the ingest node to the hub, per role

  Each switch is `1` or `0`; anything else stops the boot. The `:api` and
  `:ingester` app env keys switch a component off whatever the env says
  (the test config does).
  """

  use Application
  require Logger
  alias BBRF.{API, Env, Ingester, Role, Setup, Sync}
  alias BBRF.Ingester.Log
  alias BBRF.Ingester.Track.Strategy

  @impl true
  def start(_type, _args) do
    role = Role.current()

    %{api: api?, ingester: ingester?} =
      Role.components(role, enabled?(:api, "BBRF_API"), enabled?(:ingester, "BBRF_INGESTER"))

    strategy = if ingester?, do: Strategy.from_env()

    if ingester? or role != :all, do: Log.attach()

    :ok = BBRF.Journal.ensure!()
    :ok = Sync.use_cookie()

    children =
      [BBRF.Repo, Setup] ++
        if(api?, do: API.children(), else: []) ++
        if(ingester?, do: Ingester.children(strategy), else: []) ++
        Sync.children(role)

    Logger.info("""
    bbrf started
      - role: #{role}
      - db: #{Keyword.get(Application.get_env(:bbrf, BBRF.Repo, []), :database)}
      - #{if api?, do: API.describe(), else: "api off"}
      - #{if ingester?, do: Ingester.describe(strategy), else: "ingester off"}
      - #{Sync.describe(role)}
    """)

    Supervisor.start_link(children, strategy: :one_for_one, name: BBRF.Supervisor)
  end

  defp enabled?(key, env), do: Application.get_env(:bbrf, key, true) and Env.flag(env, true)
end
