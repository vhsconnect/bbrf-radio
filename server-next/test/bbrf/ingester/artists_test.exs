defmodule BBRF.Ingester.ArtistsTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  alias BBRF.{ArtistCredit, Metatable, Repo, TrackObservation}
  alias BBRF.Ingester.{Artists, WorkQueue}

  setup do
    Metatable.reset_db!()
    :ok
  end

  defp play(artist, title, times \\ 1) do
    Repo.insert_all(
      TrackObservation,
      for(
        _ <- 1..times,
        do:
          Metatable.observation(%{
            artist: artist,
            title: title,
            artist_credit_id: ArtistCredit.id(artist)
          })
      )
    )
  end

  defp rows(sql), do: Repo.query!(sql).rows

  describe "flatten/1" do
    test "keeps the scalar fields as columns" do
      assert Artists.flatten(Metatable.mb_artist()).artist == %{
               mbid: "mbid-beyonce",
               name: "Beyoncé",
               sort_name: "Beyoncé",
               type: "Person",
               gender: "Female",
               country: "US",
               area: "United States",
               begin_area: "Houston",
               end_area: nil,
               begin_date: "1981-09-04",
               end_date: nil,
               ended: 0,
               disambiguation: nil
             }
    end

    test "turns tags, aliases and url relations into rows, flagging genres" do
      flat = Artists.flatten(Metatable.mb_artist())

      assert flat.tags == [
               %{artist_mbid: "mbid-beyonce", tag: "american", votes: 2, genre: 0},
               %{artist_mbid: "mbid-beyonce", tag: "pop", votes: 7, genre: 1}
             ]

      assert Enum.map(flat.aliases, &{&1.alias, &1.primary_alias}) == [
               {"Beyonce", 0},
               {"ビヨンセ", 1}
             ]

      assert flat.links == [
               %{
                 artist_mbid: "mbid-beyonce",
                 url: "https://www.beyonce.com/",
                 kind: "official homepage"
               }
             ]
    end
  end

  describe "match/2" do
    test "splits a credit into its artists, in order, with their join phrases" do
      response =
        Metatable.mb_recordings([
          {100, [{"Ciara", "mbid-ciara", " & "}, {"Akeem Ali", "mbid-akeem", ""}]}
        ])

      assert Artists.match("Ciara & Akeem Ali", response) == [
               %{
                 position: 0,
                 artist_mbid: "mbid-ciara",
                 credited_as: "Ciara",
                 join_phrase: " & "
               },
               %{
                 position: 1,
                 artist_mbid: "mbid-akeem",
                 credited_as: "Akeem Ali",
                 join_phrase: ""
               }
             ]
    end

    test "skips recordings below the score threshold" do
      response =
        Metatable.mb_recordings([
          {80, [{"Queen", "mbid-queen", ""}]},
          {95, [{"Queen", "mbid-queen-2", ""}]}
        ])

      assert [%{artist_mbid: "mbid-queen-2"}] = Artists.match("Queen", response)
    end

    test "rejects a recording that credits an artist the credit does not name" do
      response = Metatable.mb_recordings([{100, [{"[unknown]", "mbid-unknown", ""}]}])

      assert Artists.match("Unknown", response) == nil
    end

    test "names an artist across quotes, accents, case and a leading the" do
      for {sent, musicbrainz} <- [
            {"GUNS N' ROSES", "Guns N’ Roses"},
            {"Celine Dion", "Céline Dion"},
            {"Beatles", "The Beatles"},
            {"Tyler， The Creator, Madison McFerrin", "Tyler, The Creator"}
          ] do
        response = Metatable.mb_recordings([{100, [{musicbrainz, "mbid-1", ""}]}])
        assert [%{artist_mbid: "mbid-1"}] = Artists.match(sent, response), sent
      end
    end

    test "names an artist only as whole words of the credit" do
      response = Metatable.mb_recordings([{100, [{"Air", "mbid-air", ""}]}])

      assert Artists.match("Fairground Attraction", response) == nil
      assert [%{artist_mbid: "mbid-air"}] = Artists.match("Air & Beck", response)
    end

    test "rejects a different artist with a similar name" do
      response = Metatable.mb_recordings([{100, [{"Gary Chester", "mbid-chester", ""}]}])

      assert Artists.match("Gary Vine", response) == nil
    end

    test "prefers the recording crediting more of the credit's artists" do
      response =
        Metatable.mb_recordings([
          {100, [{"Avicii", "mbid-avicii", " feat. "}, {"Sandro Cavazza", "mbid-sandro", ""}]},
          {97,
           [
             {"Kygo", "mbid-kygo", ", "},
             {"Avicii", "mbid-avicii", " & "},
             {"Sandro Cavazza", "mbid-sandro", ""}
           ]}
        ])

      assert Artists.match("Kygo, Avicii & Sandro Cavazza", response)
             |> Enum.map(& &1.artist_mbid) == ~w(mbid-kygo mbid-avicii mbid-sandro)
    end

    test "prefers the name with its leading the, then the artist most recordings credit" do
      response =
        Metatable.mb_recordings([
          {100, [{"Refreshments", "mbid-swedish", ""}]},
          {92, [{"The Refreshments", "mbid-other", ""}]},
          {92, [{"The Refreshments", "mbid-arizona", ""}]},
          {92, [{"The Refreshments", "mbid-arizona", ""}]}
        ])

      assert [%{artist_mbid: "mbid-arizona"}] = Artists.match("The Refreshments", response)
    end

    test "rejects the Various Artists credit" do
      response =
        Metatable.mb_recordings([
          {100, [{"Various Artists", "89ad4ac3-39f7-470e-963a-56509c546377", ""}]}
        ])

      assert Artists.match("Various artists", response) == nil
    end
  end

  describe "query/2" do
    test "searches the cleaned title as a phrase and any word of the credit" do
      assert Artists.query("Rauw Alejandro, Bizarrap", "BABY HELLO (Official Video)") ==
               ~S{recording:"BABY HELLO" AND artist:(rauw alejandro bizarrap)}
    end

    test "is nil for a credit with no words" do
      assert Artists.query(".", "Halo") == nil
    end
  end

  describe "due/2" do
    test "takes credits never tried, most played first, only from plays with a title" do
      play("Queen", "Bohemian Rhapsody", 3)
      play("Beyoncé", "Halo", 1)
      play("BEYONCÉ", "Halo", 2)
      play("Jingle", nil, 5)

      assert Enum.map(Artists.due(Metatable.now(), 10), &{&1.name, &1.title}) == [
               {"Queen", "Bohemian Rhapsody"},
               {"BEYONCÉ", "Halo"}
             ]
    end

    test "leaves out resolved credits and unresolved ones until they are due again" do
      play("Queen", "Bohemian Rhapsody")
      play("gummihuset.se", "Reklam")
      [queen, ad] = Artists.due(Metatable.now(), 10)

      Artists.store({:ok, {queen, {:resolved, [], []}}}, Metatable.now())
      Artists.store({:ok, {ad, :unresolved}}, Metatable.now())

      assert Artists.due(Metatable.now(), 10) == []

      assert [%{name: "gummihuset.se", attempts: 1}] =
               Artists.due(DateTime.add(Metatable.now(), 7, :day), 10)
    end

    test "a batch of 0 tries nothing" do
      play("Queen", "Bohemian Rhapsody")
      assert Artists.due(Metatable.now(), 0) == []
    end
  end

  describe "resolve_due/0" do
    setup do
      test_pid = self()

      plug = fn conn, _opts ->
        conn = fetch_query_params(conn)
        send(test_pid, {:request, conn.request_path})

        body =
          case conn.request_path do
            "/ws/2/recording" ->
              if conn.query_params["query"] =~ "Halo",
                do: Metatable.mb_recordings([{100, [{"Beyoncé", "mbid-beyonce", ""}]}]),
                else: Metatable.mb_recordings([])

            "/ws/2/artist/mbid-beyonce" ->
              Metatable.mb_artist()
          end

        conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(body))
      end

      server = start_supervised!({Bandit, plug: plug, ip: :loopback, port: 0, startup_log: false})
      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
      start_supervised!({WorkQueue, lanes: [musicbrainz: [max_concurrency: 1]]})

      System.put_env("MUSICBRAINZ_BASE_URL", "http://127.0.0.1:#{port}/ws/2")
      System.put_env("MUSICBRAINZ_INTERVAL_MS", "0")

      on_exit(fn ->
        System.delete_env("MUSICBRAINZ_BASE_URL")
        System.delete_env("MUSICBRAINZ_INTERVAL_MS")
      end)
    end

    test "links resolved credits to stored artists and backs off the rest" do
      play("Beyoncé", "Halo", 2)
      play("gummihuset.se", "Reklam")

      assert %{row_count: 2, inserted: 1, unchanged: 1, error: nil} = Artists.resolve_due()

      assert rows("""
             SELECT c.name, a.name, a.country
               FROM artist_credits c
               JOIN artist_credit_artists ca ON ca.artist_credit_id = c.id
               JOIN artists a ON a.mbid = ca.artist_mbid
             """) == [["Beyoncé", "Beyoncé", "US"]]

      assert rows("SELECT tag, genre FROM artist_tags ORDER BY tag") == [
               ["american", 0],
               ["pop", 1]
             ]

      assert [["unresolved", next_check_at]] =
               rows(
                 "SELECT status, next_check_at FROM artist_credits WHERE name = 'gummihuset.se'"
               )

      assert next_check_at > DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 6, :day))
    end

    test "does not look up a profile it already has" do
      play("Beyoncé", "Halo")
      Artists.resolve_due()
      assert_received {:request, "/ws/2/artist/mbid-beyonce"}

      play("BEYONCÉ feat. Nobody", "Halo")
      assert %{inserted: 1} = Artists.resolve_due()

      assert_received {:request, "/ws/2/recording"}
      refute_received {:request, "/ws/2/artist/mbid-beyonce"}
      assert rows("SELECT COUNT(*) FROM artist_credit_artists") == [[2]]
    end
  end
end
