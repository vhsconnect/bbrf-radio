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
import { endpoints, radioBrowserMirrors } from './api/radioBrowser.mjs'
import { fav } from './models/fav.mjs'
import { userAgent } from './userAgent.js'

// mutable 🚔
let server

const fastify = f({
  logger: process.env.RADIO_DEBUG ? true : { level: 'warn' },
  requestTimeout: 4000,
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
const API_VERSION = 1
let PAGINGAION_LIMIT = 5000

const write = data =>
  fs
    .writeFile(STORAGE_FILE, JSON.stringify(data), {
      encoding: 'utf-8',
    })
    .then(() => data)
    .then(R.tap(() => console.log('wrote file succesffuly ._.')))
    .catch(e => console.error('issue writing to file ' + e))

const fetchFavorites = R.identity
const fetchFavoritesLegacy = R.pipe(
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
)

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
          fs.writeFile(
            STORAGE_FILE,
            JSON.stringify({ apiVersion: API_VERSION, favorites: [] }),
            {
              encoding: 'utf-8',
            }
          )
        )
        .then(() => done())
    })
})

fastify.addHook('onReady', done => {
  fs.readFile(SETTINGS_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(R.prop('ITEMS_PER_PAGE'))
    .then(R.when(R.gt(100000)), x => {
      PAGINGAION_LIMIT = x
    })

  return fs
    .readFile(STORAGE_FILE)
    .catch(() =>
      fs.mkdir(STORAGE_DIR, { recursive: true }).then(() =>
        fs.writeFile(
          STORAGE_FILE,
          JSON.stringify({ apiVersion: API_VERSION, favorites: [] }),
          {
            encoding: 'utf-8',
          }
        )
      )
    )
    .then(() =>
      Promise.allSettled([
        Promise.race(
          radioBrowserMirrors
            .map(x => x + '/json' + endpoints.servers)
            .map(x => _got(x).json())
        ),
        fs.readFile(STORAGE_FILE),
      ])
        .then(
          R.tap(
            R.pipe(
              R.head,
              R.when(
                R.propEq('status', 'fulfilled'),
                R.pipe(
                  R.prop('value'),
                  R.head,
                  R.prop('name'),
                  R.tap(x => {
                    server = 'https://' + x
                  })
                )
              )
            )
          )
        )
        .then(
          R.pipe(
            x => x[1],
            R.when(
              R.propEq('status', 'fulfilled'),
              R.pipe(
                R.prop('value'),
                buffer => buffer.toString(),
                JSON.parse,
                R.prop('apiVersion'),
                R.ifElse(R.equals(1), R.T, () =>
                  fs.rename(STORAGE_FILE, STORAGE_FILE + '.incompat')
                ),

                () => done()
              )
            )
          )
        )
        .catch(e => {
          console.error('ERROR: ', e)
          return done()
        })
    )
})

const refetchServer = () =>
  Promise.race(
    radioBrowserMirrors
      .map(x => x + '/json' + endpoints.servers)
      .map(x => _got(x).json())
  )
    .then(
      R.pipe(
        R.head,
        R.prop('name'),
        R.tap(x => (server = 'https://' + x))
      )
    )
    .catch(e => {
      console.error('ERROR trying to fetch server: ', e)
    })

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
      refetchServer()
      return reply
        .status(500)
        .send({ error: 3, message: 'favorites unsuccessful' })
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
      refetchServer()
    })
)

fastify.get('/bytag/:tag', async (request, reply) =>
  _got(
    parse(server + '/json' + endpoints.byTagExact).expand({
      searchterm: request.params.tag,
      offset: request.query.offset * PAGINGAION_LIMIT,
      limit: PAGINGAION_LIMIT,
    })
  )
    .json()
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
      refetchServer()
    })
)

fastify.get('/bycountrycode/:cc', (request, reply) =>
  _got(
    parse(server + '/json' + endpoints.byCountrycodeExact).expand({
      searchterm: request.params.cc,
      offset: request.query.offset * PAGINGAION_LIMIT,
      limit: PAGINGAION_LIMIT,
    })
  )
    .json()
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
      refetchServer()
    })
)

fastify.get('/byname/:name', (request, reply) =>
  _got(
    parse(server + '/json' + endpoints.byName).expand({
      searchterm: request.params.name,
      offset: request.query.offset * PAGINGAION_LIMIT,
      limit: PAGINGAION_LIMIT,
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

fastify.get('/clicked/:stationuuid', async (request, reply) =>
  _got(
    parse(server + '/json' + endpoints.clickCounter).expand({
      stationuuid: request.params.stationuuid,
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

fastify.post('/write/addStation/:stationuuid', (request, reply) =>
  fs
    .readFile(STORAGE_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(store =>
      R.assoc(
        'favorites',
        store.favorites.concat(
          R.pipe(
            JSON.parse,
            R.applySpec({
              stationuuid: R.always(request.params.stationuuid),
              url: R.prop('url'),
              name: R.prop('name'),
              countrycode: R.prop('countrycode'),
              bitrate: R.prop('bitrate'),
            }),
            fav
          )(request.body)
        ),
        store
      )
    )
    .then(write)
    .then(R.prop('favorites'))
    .then(fetchFavorites)
    .then(data => reply.status(200).send(data))
    .catch(e => {
      console.log('>> ERROR >>', e)
      refetchServer()
    })
)

fastify.post('/write/removeStation/:stationuuid', (request, reply) =>
  fs
    .readFile(STORAGE_FILE)
    .then(data => data.toString())
    .then(JSON.parse)
    .then(store =>
      R.assoc(
        'favorites',
        R.reject(
          R.propEq('stationuuid', request.params.stationuuid),
          store.favorites
        ),
        store
      )
    )
    .then(write)
    .then(R.prop('favorites'))
    .then(fetchFavorites)
    .then(data => reply.status(200).send(data))
    .catch(e => {
      console.log('>> ERROR >>', e)
      refetchServer()
    })
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
    await fastify.listen({ port: Port, host: '0.0.0.0' })
  } catch (err) {
    fastify.log.error(err)
    process.exit(1)
  }
}

start()
