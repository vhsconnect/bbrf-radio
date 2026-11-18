defmodule BBRF.Ingester.Artists.CleanupTest do
  use ExUnit.Case, async: true

  alias BBRF.Ingester.Artists.Cleanup

  describe "fold/1" do
    test "spellings of one name fold the same" do
      for {sent, musicbrainz} <- [
            {"Guns N' Roses", "Guns N’ Roses"},
            {"Celine Dion", "Céline Dion"},
            {"Beatles", "The Beatles"},
            {"A.R.D.I.", "A.R.D.I"},
            {"AC; DC", "AC/DC"},
            {"Simon and Garfunkel", "Simon & Garfunkel"},
            {"Tyler， The Creator", "Tyler, The Creator"},
            {"RAG'N'BONE MAN", "Rag’n’Bone Man"}
          ] do
        assert Cleanup.fold(sent) == Cleanup.fold(musicbrainz), "#{sent} vs #{musicbrainz}"
      end
    end

    test "keeps letters of every script" do
      assert Cleanup.fold("Zivert, M’Dee") == "zivert mdee"
      assert Cleanup.fold("Двусмысленно") == "двусмысленно"
      assert Cleanup.fold("مروان معلوف") == "مروان معلوف"
    end

    test "leaves nothing of a name without letters or digits" do
      assert Cleanup.fold(" . ") == ""
    end
  end

  describe "words/1" do
    test "folds like fold/1 but keeps a leading the" do
      assert Cleanup.words("The Refreshments") == ~w(the refreshments)
      assert Cleanup.words("Guns N’ Roses") == ~w(guns n roses)
    end
  end

  describe "title/1" do
    test "drops what stations add around the title" do
      for {sent, cleaned} <- [
            {"Miracle Man (Beached Mix)", "Miracle Man"},
            {"She Moves (Far Away) (Goldfish Remix) - 9a - 121 - House-Lounge", "She Moves"},
            {"EVERYBODY LOVES THE SUNSHINE (EMMACULATE", "EVERYBODY LOVES THE SUNSHINE"},
            {"Mayilirage Mayilirage - Ah Aah [2o30]", "Mayilirage Mayilirage"},
            {"Palaco (Official Video)", "Palaco"},
            {"Flesh and Bone w/ Kitten & Hyperlink! (Live from Florida)", "Flesh and Bone"},
            {"Lemonade feat. Gunna", "Lemonade"},
            {"kill me slow (extended mix) muzter.net 128", "kill me slow 128"},
            {"Sweet Paradise LarryO Extended Remix", "Sweet Paradise"},
            {"Song A / Song B", "Song A"},
            {"Dub Be Good To Me", "Dub Be Good To Me"},
            {"Ca va ? Ca va ?", "Ca va ? Ca va ?"}
          ] do
        assert Cleanup.title(sent) == cleaned
      end
    end

    test "keeps the title as sent when cleaning would leave nothing" do
      assert Cleanup.title("(Untitled)") == "(Untitled)"
      assert Cleanup.title(" Radio Mix ") == "Radio Mix"
    end
  end

  describe "artist_terms/1" do
    test "splits a credit into plain words without joiners" do
      assert Cleanup.artist_terms("Blank & Jones Feat. Cathy Battistessa") ==
               ~w(blank jones cathy battistessa)

      assert Cleanup.artist_terms("Gunna/Don Toliver/NAV") == ~w(gunna don toliver nav)
      assert Cleanup.artist_terms("Schlagernacht :: Paul Anka") == ~w(schlagernacht paul anka)
    end

    test "leaves no Lucene syntax or operators" do
      assert Cleanup.artist_terms(~S{Earth AND Fire (+"live") \ OR*}) == ~w(earth fire live or)
    end

    test "a credit of punctuation has no terms" do
      assert Cleanup.artist_terms(" & . ") == []
    end
  end
end
