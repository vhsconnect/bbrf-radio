import React from "react";
import RadioList from "./RadioList";
import Button from "./Button";
import { fromEvent } from "rxjs";
import { debounceTime } from "rxjs/operators";

export default function Main() {
  const [channels, setChannels] = React.useState([]);
  const [tag, setTag] = React.useState("");
  const [countrycode, setCountrycode] = React.useState("");
  const [name, setName] = React.useState("");
  const [favorites, setFavorites] = React.useState([]);

  React.useEffect(() => {
    const tagsObservable = fromEvent(document.getElementById("tags"), "input");
    const ccObservable = fromEvent(
      document.getElementById("countrycode"),
      "input"
    );
    const nameObservable = fromEvent(document.getElementById("name"), "input");

    tagsObservable
      .pipe(debounceTime(1000))
      .subscribe((e) => setTag(e.target.value));

    ccObservable
      .pipe(debounceTime(1000))
      .subscribe((e) => setCountrycode(e.target.value));

    nameObservable
      .pipe(debounceTime(1000))
      .subscribe((e) => setName(e.target.value));

    const s1 = tagsObservable.subscribe(() => {
      document.getElementById("countrycode").value = ""
      document.getElementById("name").value = ""
    });
    const s2 = ccObservable.subscribe(() => {
      document.getElementById("tags").value = ""
      document.getElementById("name").value = ""
    });
    const s3 = nameObservable.subscribe(() => {
      document.getElementById("tags").value = ""
      document.getElementById("countrycode").value = ""
    });

    fetch("/favorites")
      .then((data) => data.json())
      .then(setFavorites);

    return () => {
      s1.unsubscribe();
      s2.unsubscribe();
      s3.unsubscribe();
    };
  }, []);

  React.useEffect(() => {
    const searchField = tag
      ? "tag"
      : countrycode
      ? "countrycode"
      : name
      ? "name"
      : undefined;
    const value = tag || countrycode || name;
    console.log({ value });
    if (searchField) {
      fetch(`/by${searchField}/` + value, {
        method: "GET",
      })
        .then((data) => data.json())
        .then(setChannels)
        .catch((e) => console.error(e));
    }
  }, [tag, countrycode, name]);

  return (
    <div>
      <div>
        <input className="little-" type="text" id="tags" placeholder="by tag" />
        <input
          className="little-margin"
          type="text"
          id="countrycode"
          placeholder="by country"
        />
        <input
          className="little-margin"
          type="text"
          id="name"
          placeholder="by name"
        />
        <Button
          text="favs"
          onClick={() => {
            fetch("/favorites")
              .then((data) => data.json())
              .then(setChannels);
          }}
        />
      </div>
      <RadioList favorites={favorites} channels={channels} />
    </div>
  );
}
