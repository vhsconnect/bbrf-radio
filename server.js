const fastify = require("fastify")({ logger: true });

const PORT = 3335;

fastify.register(require("fastify-static"), {
  root: __dirname,
});

fastify.get("/", async (_, reply) =>
  reply.status(200).type("text/html").sendFile("./index.html")
);

const start = async () => {
  try {
    await fastify.listen(PORT);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();
