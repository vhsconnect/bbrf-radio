defmodule BBRF.ArtistCreditTest do
  use ExUnit.Case, async: false

  alias BBRF.{ArtistCredit, Repo}

  @before_credits 20_261_021_120_007

  test "spellings that differ only in case, spacing or composition share an id" do
    assert ArtistCredit.id("Beyoncé") == ArtistCredit.id("  BEYONCÉ ")
    assert ArtistCredit.id("Ciara & Akeem Ali") == ArtistCredit.id("ciara  &  akeem ali")
    refute ArtistCredit.id("Ciara & Akeem Ali") == ArtistCredit.id("Ciara")
  end

  test "ids are non-negative and there is none for a missing or blank artist" do
    assert ArtistCredit.id("Queen") >= 0
    assert ArtistCredit.id(nil) == nil
    assert ArtistCredit.id("   ") == nil
  end

  test "the migration stamps every existing observation with its credit" do
    repo = start_supervised!({Repo, name: nil, database: ":memory:", pool_size: 1})
    previous = Repo.put_dynamic_repo(repo)
    on_exit(fn -> Repo.put_dynamic_repo(previous) end)

    Code.put_compiler_option(:ignore_module_conflict, true)
    migrate = &Ecto.Migrator.run(Repo, :up, Keyword.merge([dynamic_repo: repo, log: false], &1))
    migrate.(to: @before_credits)

    Repo.query!("""
    INSERT INTO track_observations (stationuuid, observed_at, artist, title)
    VALUES ('s', '2026-10-29', 'Queen', 'Bohemian Rhapsody'), ('s', '2026-10-29', NULL, 'Jingle')
    """)

    migrate.(all: true)
    Code.put_compiler_option(:ignore_module_conflict, false)

    assert Repo.query!("SELECT artist_credit_id FROM track_observations ORDER BY id").rows ==
             [[ArtistCredit.id("Queen")], [nil]]
  end
end
