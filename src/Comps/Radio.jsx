import React from "react";
import Button from "./Button";
import * as R from "ramda";

const Radio = ({ info, favorites }) => {
  console.log(favorites);
  const isFav = R.includes(info.stationuuid)(
    R.map(R.prop("stationuuid"), favorites)
  );
  return (
    <div>
      <p>{info.name}</p>
      <div className="flex">
        <audio src={info["url_resolved"]} preload="none" controls>
          browser issues?
        </audio>
        <div>
          <Button
            disabled={isFav}
            text="🌟"
            onClick={() => {
              fetch("/write/addStation/" + info.stationuuid, {
                method: "POST",
              });
            }}
          />
          <Button
            disabled={!isFav}
            text="🚮"
            onClick={() => {
              fetch("/write/removeStation/" + info.stationuuid, {
                method: "POST",
              });
            }}
          />
        </div>
      </div>
    </div>
  );
};

export default Radio;
