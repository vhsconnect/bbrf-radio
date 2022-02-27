#!/usr/bin/env node
import * as fs from "fs/promises";
import { fileURLToPath } from "url";
import { dirname, normalize } from "path";
import f from "fastify";
import fastifyStatic from "fastify-static";
import got from "got";
import * as R from "ramda";
import { parse } from "uri-template";
import { server, endpoints } from "./api/radioBrowser.js";

const fastify = f({ logger: true });
const PORT = 3335;
const STORAGE_FILE = `${dirname(fileURLToPath(import.meta.url))}/storage.json`;

fastify.register(fastifyStatic, {
  root: R.pipe(
    fileURLToPath,
    R.concat(R.__, "/.."),
    normalize,
    dirname
  )(import.meta.url),
});

fastify.addHook("onRequest", (_, __, done) => {
  fs.readFile(STORAGE_FILE)
    .then(() => done())
    .catch(() => {
      fs.writeFile(STORAGE_FILE, JSON.stringify({}), {
        encoding: "utf-8",
      })
        .then(() => done());
    });
});

fastify.get("/", async (_, reply) => {
  reply.status(200).type("text/html").sendFile("./index.html");
});

fastify.get("/favorites", (_, reply) => {
  fs.readFile(STORAGE_FILE)
    .then((data) => data.toString())
    .then(JSON.parse)
    .then(R.prop("favorites"))
    .then(R.join(","))
    .then((data) => parse(endpoints.byUUIDS).expand({ uuids: data }))
    .then((data) => got(server + "/json/" + data).json())
    .then((value) => reply.status(200).send(value));
});

fastify.get("/stations", async (_, reply) =>
  got(server + "/json" + endpoints.allStations)
    .json()
    .then((value) => reply.status(200).send(value))
    .catch((e) => {
      reply.status(500).send({
        error: e,
        message: "something went wrong",
      });
    })
);

fastify.get("/bytag/:tag", async (request, reply) => {
  console.log("sever goes ._.");
  got(
    parse(server + "/json" + endpoints.byTagExact).expand({
      searchterm: request.params.tag,
    })
  )
    .json()
    .then((value) => reply.status(200).send(value))
    .catch((e) => {
      reply.status(500).send({
        error: e,
        message: "something went wrong",
      });
    });
});

fastify.get("/bycountrycode/:cc", async (request, reply) => {
  console.log("sever goes ._.");
  got(
    parse(server + "/json" + endpoints.byCountrycodeExact).expand({
      searchterm: request.params.cc,
    })
  )
    .json()
    .then((value) => reply.status(200).send(value))
    .catch((e) => {
      reply.status(500).send({
        error: e,
        message: "something went wrong",
      });
    });
});

fastify.get("/byname/:name", async (request, reply) => {
  console.log("sever goes ._.");
  got(
    parse(server + "/json" + endpoints.byName).expand({
      searchterm: request.params.name,
    })
  )
    .json()
    .then((value) => reply.status(200).send(value))
    .catch((e) => {
      reply.status(500).send({
        error: e,
        message: "something went wrong",
      });
    });
});

fastify.get("/clicked/:uuid", async (request, reply) => {
  console.log("sever goes ._.");
  got(
    parse(server + "/json" + endpoints.clickCounter).expand({
      stationuuid: request.params.uuid,
    })
  )
    .json()
    .then((value) => reply.status(200).send(value))
    .catch((e) => {
      reply.status(500).send({
        error: e,
        message: "something went wrong",
      });
    });
});

fastify.post("/write/addStation/:uuid", (request, reply) => {
  fs.readFile(STORAGE_FILE)
    .then((data) => data.toString())
    .then(JSON.parse)
    .then((store) =>
      R.assoc("favorites", store.favorites.concat(request.params.uuid), store)
    )
    .then(JSON.stringify)
    .then((data) =>
      fs.writeFile(
        STORAGE_FILE,
        data,
        { encoding: "utf-8" }
      )
    )
    .then(() => console.log("wrote file succesffuly ._."))
    .then(() => reply.status(200).send())
    .catch((e) => console.log(">> ERROR >>", e));
});

fastify.post("/write/removeStation/:uuid", (request, reply) => {
  fs.readFile(STORAGE_FILE)
    .then((data) => data.toString())
    .then(JSON.parse)
    .then((store) =>
      R.assoc(
        "favorites",
        R.reject(R.equals(request.params.uuid), store.favorites),
        store
      )
    )
    .then(JSON.stringify)
    .then((data) =>
      fs.writeFile(
        STORAGE_FILE,
        data,
        { encoding: "utf-8" }
      )
    )
    .then(() => console.log("wrote file succesffuly ._."))
    .then(() => reply.status(200).send())
    .catch((e) => console.log(">> ERROR >>", e));
});

const start = async () => {
  try {
    await fastify.listen(PORT);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();