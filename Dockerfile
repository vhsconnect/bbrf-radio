FROM node:22-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm ci --only=production

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Production stage
FROM node:22-alpine

WORKDIR /app

# Install production dependencies only
COPY package*.json ./
RUN npm ci --only=production

# Copy built files from builder
COPY --from=builder /app/index.js ./
COPY --from=builder /app/index.html ./
COPY --from=builder /app/styles.css ./
COPY --from=builder /app/favicon-16x16.png ./
COPY --from=builder /app/server ./server

# Create data directory structure
RUN mkdir -p /app/data/bbrf-radio

# Create default settings.json with port 4881
RUN echo '{"FADER_VALUE": 25, "PORT": 4881, "ITEM_PER_PAGE": 2000}' > /app/data/bbrf-radio/settings.json

# Set environment variable for XDG config directory
ENV XDG_CONFIG_HOME=/app/data

# Expose port
EXPOSE 4881

# Start the server
CMD ["node", "server/server.mjs"]