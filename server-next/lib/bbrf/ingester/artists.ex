defmodule BBRF.Ingester.Artists do
  @moduledoc """
  Resolves artist credits (`BBRF.ArtistCredit`) to MusicBrainz artists,
  most played first, in the `:musicbrainz` lane of
  `BBRF.Ingester.WorkQueue`.

  A recording search on a credit's most played title and the words of
  the credit, both cleaned up by `BBRF.Ingester.Artists.Cleanup`,
  returns MusicBrainz's own split of the credit into artists. The best
  match is taken when it scores at least 90 and every artist in it is
  named in the credit as whole words, once both are folded, and none is
  a special purpose artist ([unknown], Various Artists, ...); otherwise
  the credit is unresolved and tried
  again after 7 days, then every 30, since an ad or a placeholder never
  resolves. Each artist not in `artists` yet has its profile looked up
  and stored flattened over `artists` and the `artist_*` tables.

  Every ARTIST_RESOLVE_MINUTES (10), up to ARTIST_RESOLVE_BATCH (300)
  credits are tried; 0 turns the resolver off. A credit whose requests
  fail is left as it was and comes up again on the next round.
  """

  require Logger
  alias BBRF.{Env, IngestStat, MusicBrainz, Repo}
  alias BBRF.Ingester.Artists.Cleanup
  alias BBRF.Ingester.WorkQueue

  @min_score 90
  @various_artists "89ad4ac3-39f7-470e-963a-56509c546377"
  @unresolved_days [7, 30]
  @profile_inc ~w(aliases tags genres url-rels)
  # a search plus a profile lookup per artist, each paced a second apart
  @job_timeout_ms 120_000

  def interval_minutes, do: Env.int("ARTIST_RESOLVE_MINUTES", 10)
  def batch_size, do: Env.int("ARTIST_RESOLVE_BATCH", 300)

  @doc """
  One round over the credits due. Records stats in ingest_stats under
  'artist-resolve'; never throws.
  """
  def resolve_due do
    try do
      start = System.monotonic_time(:millisecond)
      credits = due(DateTime.utc_now(), batch_size())

      counts =
        WorkQueue
        |> WorkQueue.async_stream(:musicbrainz, credits, &{&1, resolve(&1)},
          timeout: @job_timeout_ms
        )
        |> Enum.reduce(%{}, fn element, counts ->
          Map.update(counts, store(element, DateTime.utc_now()), 1, &(&1 + 1))
        end)

      count = &Map.get(counts, &1, 0)

      stats = %{
        row_count: length(credits),
        inserted: count.(:resolved),
        updated: 0,
        unchanged: count.(:unresolved),
        duration_ms: System.monotonic_time(:millisecond) - start,
        error: if(count.(:failed) > 0, do: "failed=#{count.(:failed)}")
      }

      IngestStat.record("artist-resolve", stats)
      stats
    rescue
      exception ->
        Logger.error("artist resolve failed: #{Exception.message(exception)}")
        nil
    end
  end

  @doc """
  The credits to try at `now`, most played first, at most `limit`: those
  never tried and the unresolved ones due again, each with the spelling
  and title it was played with most.
  """
  def due(_now, limit) when limit <= 0, do: []

  def due(now, limit) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT o.artist_credit_id, COALESCE(c.attempts, 0)
          FROM track_observations o
          LEFT JOIN artist_credits c ON c.id = o.artist_credit_id
         WHERE o.artist_credit_id IS NOT NULL
           AND o.title IS NOT NULL
           AND (c.id IS NULL OR (c.status = 'unresolved' AND c.next_check_at <= ?))
         GROUP BY o.artist_credit_id
         ORDER BY COUNT(*) DESC, o.artist_credit_id
         LIMIT ?
        """,
        [DateTime.to_iso8601(now), limit]
      )

    Enum.map(rows, fn [id, attempts] ->
      %{rows: [[name, title]]} =
        Repo.query!(
          """
          SELECT artist, title
            FROM track_observations
           WHERE artist_credit_id = ? AND title IS NOT NULL
           GROUP BY artist, title
           ORDER BY COUNT(*) DESC, artist, title
           LIMIT 1
          """,
          [id]
        )

      %{id: id, name: name, title: title, attempts: attempts}
    end)
  end

  @doc """
  Ask MusicBrainz who `credit` is: `{:resolved, artists, profiles}` with
  the credit's artists in order and the flattened profiles of those not
  stored yet, or `:unresolved`. Raises when a request fails.
  """
  def resolve(%{name: name, title: title}) do
    with query when query != nil <- query(name, title),
         artists when artists != nil <-
           match(name, MusicBrainz.search(:recording, query, limit: 10)),
         profiles when profiles != nil <- new_profiles(artists) do
      {:resolved, artists, profiles}
    else
      nil -> :unresolved
    end
  end

  @doc """
  The recording search for a credit `name` played with `title`: the
  cleaned title as a phrase and any of the credit's words as the artist.
  nil when the credit has no words to search with.
  """
  def query(name, title) do
    case Cleanup.artist_terms(name) do
      [] ->
        nil

      terms ->
        "recording:#{MusicBrainz.phrase(Cleanup.title(title))} AND artist:(#{Enum.join(terms, " ")})"
    end
  end

  # nil when an artist has no profile (merged away since the search)
  defp new_profiles(artists) do
    mbids = artists |> Enum.map(& &1.artist_mbid) |> Enum.uniq()

    Enum.reduce_while(mbids -- known(mbids), [], fn mbid, profiles ->
      case MusicBrainz.lookup(:artist, mbid, inc: @profile_inc) do
        nil -> {:halt, nil}
        profile -> {:cont, [flatten(profile) | profiles]}
      end
    end)
  end

  defp known(mbids) do
    placeholders = Enum.map_join(mbids, ", ", fn _ -> "?" end)
    %{rows: rows} = Repo.query!("SELECT mbid FROM artists WHERE mbid IN (#{placeholders})", mbids)
    List.flatten(rows)
  end

  @doc """
  The artists of a recording in a search `response` that scores at least
  #{@min_score} and names no artist the credit `name` leaves out, as
  `artist_credit_artists` rows without the credit id; nil for none.

  Of several, the one whose artists account for the most words of the
  credit wins ("The Refreshments" over "Refreshments", all three of
  "Kygo, Avicii & Sandro Cavazza" over two of them), then the artists
  the most of those recordings credit, then the best scored.
  """
  def match(name, response) do
    key = " #{Cleanup.fold(name)} "

    credits =
      for recording <- response["recordings"] || [],
          credit = recording["artist-credit"] || [],
          score(recording) >= @min_score and credit != [] and Enum.all?(credit, &named?(key, &1)),
          do: credit

    case credits do
      [] -> nil
      credits -> credits |> best(Cleanup.words(name)) |> credit_rows()
    end
  end

  defp best(credits, words) do
    words = Enum.uniq(words)
    counts = Enum.frequencies_by(credits, &mbids/1)
    Enum.max_by(credits, &{coverage(&1, words), counts[mbids(&1)]})
  end

  defp mbids(credit), do: Enum.map(credit, & &1["artist"]["id"])

  defp coverage(credit, words) do
    named =
      Enum.flat_map(
        credit,
        &(Cleanup.words(&1["name"] || "") ++ Cleanup.words(&1["artist"]["name"] || ""))
      )

    Enum.count(words, &(&1 in named))
  end

  defp credit_rows(credit) do
    credit
    |> Enum.with_index()
    |> Enum.map(fn {entry, position} ->
      %{
        position: position,
        artist_mbid: entry["artist"]["id"],
        credited_as: entry["name"],
        join_phrase: entry["joinphrase"]
      }
    end)
  end

  defp score(%{"score" => score}) when is_integer(score), do: score
  defp score(%{"score" => score}) when is_binary(score), do: String.to_integer(score)
  defp score(_recording), do: 0

  defp named?(key, entry) do
    not special?(entry["artist"]) and
      (contains?(key, entry["name"]) or contains?(key, entry["artist"]["name"]))
  end

  defp special?(%{"id" => @various_artists}), do: true
  defp special?(%{"name" => "[" <> _rest}), do: true
  defp special?(_artist), do: false

  defp contains?(_key, nil), do: false

  defp contains?(key, name) do
    case Cleanup.fold(name) do
      "" -> false
      name -> String.contains?(key, " #{name} ")
    end
  end

  @doc """
  A MusicBrainz artist lookup as rows: `artist` for `artists`, and the
  `tags` (genres flagged), `aliases` and `links` of its child tables.
  """
  def flatten(profile) do
    mbid = profile["id"]
    life = profile["life-span"] || %{}
    genres = Map.new(profile["genres"] || [], &{&1["name"], &1["count"]})
    tags = Map.new(profile["tags"] || [], &{&1["name"], &1["count"]})

    %{
      artist: %{
        mbid: mbid,
        name: profile["name"],
        sort_name: profile["sort-name"],
        type: profile["type"],
        gender: profile["gender"],
        country: profile["country"],
        area: area(profile["area"]),
        begin_area: area(profile["begin-area"]),
        end_area: area(profile["end-area"]),
        begin_date: life["begin"],
        end_date: life["end"],
        ended: flag(life["ended"] == true),
        disambiguation: blank_to_nil(profile["disambiguation"])
      },
      tags:
        tags
        |> Map.merge(genres)
        |> Enum.sort()
        |> Enum.map(fn {tag, votes} ->
          %{artist_mbid: mbid, tag: tag, votes: votes || 0, genre: flag(is_map_key(genres, tag))}
        end),
      aliases:
        (profile["aliases"] || [])
        |> Enum.uniq_by(& &1["name"])
        |> Enum.map(fn alias_entry ->
          %{
            artist_mbid: mbid,
            alias: alias_entry["name"],
            locale: alias_entry["locale"],
            primary_alias: flag(alias_entry["primary"] == true)
          }
        end),
      links:
        for(
          %{"target-type" => "url", "url" => %{"resource" => url}} = relation <-
            profile["relations"] || [],
          do: %{artist_mbid: mbid, url: url, kind: relation["type"]}
        )
        |> Enum.uniq_by(& &1.url)
    }
  end

  defp area(%{"name" => name}), do: name
  defp area(_none), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # exqlite binds a boolean as the text 'true' or 'false'
  defp flag(true), do: 1
  defp flag(false), do: 0

  # ---------------------------------------------------------------------------
  # Storage
  # ---------------------------------------------------------------------------

  @doc "Store what resolving one credit found; returns :resolved, :unresolved or :failed."
  def store({:ok, {credit, {:resolved, artists, profiles}}}, now) do
    {:ok, _} =
      Repo.transaction(fn ->
        Enum.each(profiles, &store_profile(&1, now))
        upsert_credit(credit, "resolved", now, nil)
        Repo.query!("DELETE FROM artist_credit_artists WHERE artist_credit_id = ?", [credit.id])

        Repo.insert_all(
          "artist_credit_artists",
          Enum.map(artists, &Map.put(&1, :artist_credit_id, credit.id))
        )
      end)

    :resolved
  end

  def store({:ok, {credit, :unresolved}}, now) do
    days = Enum.at(@unresolved_days, min(credit.attempts, length(@unresolved_days) - 1))
    upsert_credit(credit, "unresolved", now, DateTime.add(now, days, :day))
    :unresolved
  end

  def store({:exit, {credit, reason}}, _now) do
    Logger.debug("artist credit #{inspect(credit.name)} failed: #{inspect(reason)}")
    :failed
  end

  defp upsert_credit(credit, status, now, next_check_at) do
    Repo.query!(
      """
      INSERT INTO artist_credits (id, name, status, attempts, checked_at, next_check_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE
         SET name = excluded.name,
             status = excluded.status,
             attempts = excluded.attempts,
             checked_at = excluded.checked_at,
             next_check_at = excluded.next_check_at
      """,
      [
        credit.id,
        credit.name,
        status,
        credit.attempts + 1,
        DateTime.to_iso8601(now),
        next_check_at && DateTime.to_iso8601(next_check_at)
      ]
    )
  end

  defp store_profile(%{artist: artist, tags: tags, aliases: aliases, links: links}, now) do
    row = Map.put(artist, :fetched_at, DateTime.to_iso8601(now))

    Repo.insert_all("artists", [row],
      on_conflict: {:replace, Map.keys(row) -- [:mbid]},
      conflict_target: [:mbid]
    )

    for {table, rows} <- [artist_tags: tags, artist_aliases: aliases, artist_links: links] do
      Repo.query!("DELETE FROM #{table} WHERE artist_mbid = ?", [artist.mbid])
      Repo.insert_all(Atom.to_string(table), rows)
    end
  end
end
