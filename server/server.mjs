#!/usr/bin/env node

import * as fs from 'fs/promises'
import { fileURLToPath } from 'url'
import { dirname, normalize } from 'path'
import dns from 'dns'
import util from 'util'
import f from 'fastify'
import fastifyStatic from '@fastify/static'
import * as R from 'ramda'
import xdg from 'xdg-portable'
import { radioApi } from './api/radioBrowser.mjs'
import { fav } from './models/fav.mjs'
const resolveSrv = util.promisify(dns.resolveSrv)

// global 🚔
let server
let storageFile

const fastify = f({
  logger: process.env.RADIO_DEBUG ? true : { level: 'warn' },
  requestTimeout: 4000,
})

const DEFAULT_PORT = 3335
const STORAGE_DIR = `${xdg.config()}/bbrf-radio/`
const STORAGE_FILE = `${xdg.config()}/bbrf-radio/storage.json`
const SETTINGS_FILE = `${xdg.config()}/bbrf-radio/settings.json`
const API_VERSION = 1
let PAGINATION_LIMIT = 5000

const write = data =>
  fs
    .writeFile(STORAGE_FILE, JSON.stringify(data), {
      encoding: 'utf-8',
    })
    .then(() => data)
    .then(R.tap(() => console.log('wrote file succesffuly ._.')))
    .catch(e => console.error('issue writing to file ' + e))

fastify.register(fastifyStatic, {
  root: R.pipe(
    fileURLToPath,
    R.concat(R.__, '/..'),
    normalize,
    dirname
  )(import.meta.url),
})

const fetchServer = () =>
  R.pipe(
    resolveSrv,
    R.andThen(
      R.pipe(
        R.head,
        R.prop('name'),
        R.tap(x => {
          server = x
        })
      )
    )
  )('_api._tcp.radio-browser.info')

const storageIsInit = R.when(R.isNil(), () =>
  fs
    .readFile(STORAGE_FILE)
    .then(() => {
      storageFile = true
    })
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
        .then(() => {
          storageFile = true
        })
    })
)

const upstreamIsInit = R.when(R.isNil, fetchServer)

fastify.addHook('onRequest', async (_, __) => {
  await storageIsInit(storageFile)
  await upstreamIsInit(server)
})

fastify.addHook('onReady', async () => {
  await fs
    .readFile(SETTINGS_FILE, (err, data) => {
      if (err) throw err
      return data
    })
    .then(data => data.toString())
    .then(JSON.parse)
    .then(R.prop('ITEMS_PER_PAGE'))
    .then(
      R.when(R.either(R.gt(100000), R.lt(500)), x => {
        PAGINATION_LIMIT = x
      })
    )
    .catch(e => {
      console.log(`reading ${SETTINGS_FILE} failed: ${e}`)
    })
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
    .then(x => reply.status(200).send(JSON.stringify({ value: x })))
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
        R.when(R.isEmpty, favorites => reply.status(200).send(favorites))
      )
    )
    .then(data => reply.status(200).send(data))
    .catch(() => {
      fetchServer()
      return reply
        .status(500)
        .send({ error: 3, message: 'favorites unsuccessful' })
    })
})

fastify.get('/stations', async (_, reply) =>
  radioApi
    .getAllStations(server)
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
      fetchServer()
    })
)

fastify.get('/bytag/:tag', async (request, reply) =>
  radioApi
    .getByTag(
      server,
      request.params.tag,
      request.query.offset,
      PAGINATION_LIMIT
    )
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
      fetchServer()
    })
)

fastify.get('/bycountrycode/:cc', (request, reply) =>
  radioApi
    .getByCountryCode(
      server,
      request.params.cc,
      request.query.offset,
      PAGINATION_LIMIT
    )
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
      fetchServer()
    })
)

fastify.get('/byname/:name', (request, reply) =>
  radioApi
    .getByName(
      server,
      request.params.name,
      request.query.offset,
      PAGINATION_LIMIT
    )
    .then(value => reply.status(200).send(value))
    .catch(e => {
      reply.status(500).send({
        error: e,
        message: 'something went wrong',
      })
    })
)

fastify.get('/clicked/:stationuuid', async (request, reply) =>
  radioApi
    .clickStation(server, request.params.stationuuid)
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
    .then(data => reply.status(200).send(data))
    .catch(e => {
      console.log('>> ERROR >>', e)
      fetchServer()
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
          R.propEq(request.params.stationuuid, 'stationuuid'),
          store.favorites
        ),
        store
      )
    )
    .then(write)
    .then(R.prop('favorites'))
    .then(data => reply.status(200).send(data))
    .catch(e => {
      console.log('>> ERROR >>', e)
      fetchServer()
    })
)

const start = async () => {
  try {
    const Port = await fs
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
