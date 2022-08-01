#!/usr/bin/env node
import * as fs from 'fs/promises'
import { fileURLToPath } from 'url'
import { dirname, normalize } from 'path'
import f from 'fastify'
import fastifyStatic from '@fastify/static'
import got from 'got'
import * as R from 'ramda'
import { parse } from 'uri-template'
import {
  endpoints,
  mainServer,
  radioBrowserMirrors,
} from './api/radioBrowser.js'
import { fav } from './models/fav.js'

// mutable 🚔
let server = mainServer

const fastify = f({
  logger: process.env.RADIO_DEBUG ? true : { level: 'warn' },
})
const PORT = 3335
const STORAGE_FILE = `${dirname(fileURLToPath(import.meta.url))}/storage.json`

const writeToFileSideEffect = data =>
  fs
    .writeFile(STORAGE_FILE, JSON.stringify(data), {
      encoding: 'utf-8',
    })
    .then(() => console.log('wrote file succesffuly ._.'))
    .catch(e => console.error('issue writing to file ' + e))

const fetchFavorites = favorites =>
  R.pipe(
    R.pluck('id'),
    R.join(','),
    data => parse(endpoints.byUUIDS).expand({ uuids: data }),
    data =>
      got(server + '/json/' + data)
        .json()
        .then(
          R.map(x => ({
            ...x,
            ...R.find(R.propEq('id', x.stationuuid), favorites),
          }))
        )
  )(favorites)

fastify.register(fastifyStatic, {
  root: R.pipe(
    fileURLToPath,
    R.concat(R.__, '/..'),
    normalize,
    dirname
  )(import.meta.url),
})

fastify.addHook('onRequest', (_, __, done) => {
  fs.readFile(STORAGE_FILE)
    .then(() => done())
    .catch(() => {
      fs.writeFile(STORAGE_FILE, JSON.stringify({ favorites: [] }), {
        encoding: 'utf-8',
      }).then(() => done())
    })
})

fastify.addHook('onRequest', (req, _, done) => {
  req.headers = {
    ...req.headers,
    'user-agent': 'vhsconnect/bbrf-radio v0.0.1',
  }
  done()
})

fastify.addHook('onReady', done =>
  Promise.race(
    radioBrowserMirrors
      .map(x => x + '/json' + endpoints.servers)
      .map(x => got(x).json())
  )
    .then(
      R.pipe(
        R.head,
        R.prop('name'),
        R.tap(x => (server = 'https://' + x)),
        () => done()
      )
    )
    .catch(e => {
      console.error('ERROR trying to fetch server: ', e)
      done()
    })
)

fastify.get('/', async (_, reply) =>
  reply
    .headers({ radioBowserServer: server })
    .status(200)
    .type('text/html')
    .sendFile('./index.html')
)

fastify.get('/favorites', (_, reply) => {
  return fs
    .readFile(STORAGE_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(
      R.pipe(
        R.prop('favorites'),
        R.ifElse(
          R.isEmpty,
          favorites => reply.status(200).send(favorites),
          fetchFavorites
        )
      )
    )
    .then(data => reply.status(200).send(data))
    .catch(e => {
      console.error('favorites', e)
      reply.status(500)
    })
})

fastify.get('/stations', async (_, reply) =>
  got(server + '/json' + endpoints.allStations)
    .json()
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
    })
)

fastify.get('/bytag/:tag', async (request, reply) =>
  got(
    parse(server + '/json' + endpoints.byTagExact).expand({
      searchterm: request.params.tag,
    })
  )
    .json()
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
    })
)

fastify.get('/bycountrycode/:cc', (request, reply) =>
  got(
    parse(server + '/json' + endpoints.byCountrycodeExact).expand({
      searchterm: request.params.cc,
    })
  )
    .json()
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
    })
)

fastify.get('/byname/:name', (request, reply) =>
  got(
    parse(server + '/json' + endpoints.byName).expand({
      searchterm: request.params.name,
    })
  )
    .json()
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
    })
)

fastify.get('/clicked/:uuid', async (request, reply) =>
  got(
    parse(server + '/json' + endpoints.clickCounter).expand({
      stationuuid: request.params.uuid,
    })
  )
    .then(data => reply.status(200).send(data))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
    })
)

fastify.get('/radio-server', (_, reply) => reply.status(200).send({ server }))

fastify.post('/write/addStation/:uuid', (request, reply) =>
  fs
    .readFile(STORAGE_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(store =>
      R.assoc(
        'favorites',
        store.favorites.concat(
          fav({
            id: request.params.uuid,
            with20delay: false,
            with30delay: false,
          })
        ),
        store
      )
    )
    .then(R.tap(writeToFileSideEffect))
    .then(R.prop('favorites'))
    .then(fetchFavorites)
    .then(data => reply.status(200).send(data))
    .catch(e => console.log('>> ERROR >>', e))
)

fastify.post('/write/removeStation/:uuid', (request, reply) =>
  fs
    .readFile(STORAGE_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(store =>
      R.assoc(
        'favorites',
        R.reject(R.propEq('id', request.params.uuid), store.favorites),
        store
      )
    )
    .then(R.tap(writeToFileSideEffect))
    .then(R.prop('favorites'))
    .then(fetchFavorites)
    .then(data => reply.status(200).send(data))
    .catch(e => console.log('>> ERROR >>', e))
)

// currently unused
fastify.put('/write/add20/:uuid', (request, reply) =>
  fs
    .readFile(STORAGE_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(store =>
      R.assoc(
        'favorites',
        R.map(
          R.when(R.propEq('id', request.params.uuid), x => ({
            ...x,
            with20delay: true,
          }))
        )(store.favorites),
        store
      )
    )
    .then(R.tap(writeToFileSideEffect))
    .then(R.prop('favorites'))
    .then(fetchFavorites)
    .then(data => reply.status(200).send(data))
    .catch(e => console.log('>> ERROR >>', e))
)

fastify.put('/write/schedule/:uuid/:timestamp', (request, reply) =>
  fs
    .readFile(STORAGE_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(store =>
      R.assoc(
        'favorites',
        R.map(
          R.when(R.propEq('id', request.params.uuid), x => ({
            ...x,
            scheduled: request.params.timestamp,
          }))
        )(store.favorites),
        store
      )
    )
    .then(R.tap(writeToFileSideEffect))
    .then(R.prop('favorites'))
    .then(fetchFavorites)
    .then(data => reply.status(200).send(data))
    .catch(e => console.log('>> ERROR >>', e))
)

fastify.put('/write/remove-schedule/:uuid', (request, reply) =>
  fs
    .readFile(STORAGE_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(store =>
      R.assoc(
        'favorites',
        R.map(
          R.when(R.propEq('id', request.params.uuid), x => ({
            ...x,
            scheduled: undefined,
          }))
        )(store.favorites),
        store
      )
    )
    .then(R.tap(writeToFileSideEffect))
    .then(R.prop('favorites'))
    .then(fetchFavorites)
    .then(data => reply.status(200).send(data))
    .catch(e => console.log('>> ERROR >>', e))
)

const start = async () => {
  try {
    await fastify.listen(PORT)
  } catch (err) {
    fastify.log.error(err)
    process.exit(1)
  }
}

start()
