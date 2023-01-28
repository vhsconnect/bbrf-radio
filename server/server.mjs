#!/usr/bin/env node

import * as fs from 'fs/promises'
import { fileURLToPath } from 'url'
import { dirname, normalize } from 'path'
import f from 'fastify'
import fastifyStatic from '@fastify/static'
import got from 'got'
import * as R from 'ramda'
import { parse } from 'uri-template'
import xdg from 'xdg-portable'
import {
  endpoints,
  mainServer,
  radioBrowserMirrors,
} from './api/radioBrowser.mjs'
import { fav } from './models/fav.mjs'
import { userAgent } from './userAgent.js'

// mutable 🚔
let server = mainServer

const fastify = f({
  logger: process.env.RADIO_DEBUG ? true : { level: 'warn' },
})

const _got = got.extend({
  hooks: {
    init: [
      (_, options) => {
        options.headers = {
          ...options.headers,
          'user-agent': userAgent,
        }
      },
    ],
  },
})

const DEFAULT_PORT = 3335
const STORAGE_DIR = `${xdg.config()}/bbrf-radio/`
const STORAGE_FILE = `${xdg.config()}/bbrf-radio/storage.json`
const SETTINGS_FILE = `${xdg.config()}/bbrf-radio/settings.json`

const write = data =>
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
      _got(server + '/json/' + data)
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
      fs.mkdir(STORAGE_DIR, { recursive: true })
        .then(() =>
          fs.writeFile(STORAGE_FILE, JSON.stringify({ favorites: [] }), {
            encoding: 'utf-8',
          })
        )
        .then(() => done())
    })
})

fastify.addHook('onReady', done =>
  Promise.race(
    radioBrowserMirrors
      .map(x => x + '/json' + endpoints.servers)
      .map(x => _got(x).json())
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

fastify.get('/fader', (_, reply) =>
  fs
    .readFile(SETTINGS_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(R.prop('FADER_VALUE'))
    .then(x => reply.status(200).send(x))
    .catch(() => reply.status(202).send(25))
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
  _got(server + '/json' + endpoints.allStations)
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
  _got(
    parse(server + '/json' + endpoints.byTagExact).expand({
      searchterm: request.params.tag,
      offset: request.query.offset * 200,
      limit: 200,
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
  _got(
    parse(server + '/json' + endpoints.byCountrycodeExact).expand({
      searchterm: request.params.cc,
      offset: request.query.offset * 200,
      limit: 200,
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
  _got(
    parse(server + '/json' + endpoints.byName).expand({
      searchterm: request.params.name,
      offset: request.query.offset * 200,
      limit: 200,
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
  _got(
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
    .then(R.tap(write))
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
    .then(R.tap(write))
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
    .then(R.tap(write))
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
    .then(R.tap(write))
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
    .then(R.tap(write))
    .then(R.prop('favorites'))
    .then(fetchFavorites)
    .then(data => reply.status(200).send(data))
    .catch(e => console.log('>> ERROR >>', e))
)

const start = async () => {
  try {
    let Port = await fs
      .readFile(SETTINGS_FILE)
      .then(data => data.toString())
      .then(JSON.parse)
      .then(R.prop('PORT'))
      .catch(() => {
        console.log('no custom port specified')
        return DEFAULT_PORT
      })
    await fastify.listen(Port)
  } catch (err) {
    fastify.log.error(err)
    process.exit(1)
  }
}

start()
