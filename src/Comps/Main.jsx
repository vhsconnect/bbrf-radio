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
    fromEvent(document.getElementById("tags"), "input")
      .pipe(debounceTime(1000))
      .subscribe((e) => setTag(e.target.value));
    fromEvent(document.getElementById("countrycode"), "input")
      .pipe(debounceTime(1000))
      .subscribe((e) => setCountrycode(e.target.value));
    fromEvent(document.getElementById("name"), "input")
      .pipe(debounceTime(1000))
      .subscribe((e) => setName(e.target.value));
    fetch("/favorites")
      .then((data) => data.json())
      .then(setFavorites)
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
      <input type="text" id="tags" placeholder="by tag" />
      <input type="text" id="countrycode" placeholder="by country" />
      <input type="text" id="name" placeholder="by name" />
      <Button
        text="favs"
        onClick={() => {
          fetch("/favorites")
            .then((data) => data.json())
            .then(setChannels);
        }}
      />
      <RadioList favorites={favorites} channels={channels} />
    </div>
  );
}
