# Use Node.js 20 LTS as the base image
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Install git (needed for some dependencies)
RUN apk add --no-cache git

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN npm ci --only=production=false

# Copy project files
COPY . .

# Compile contracts
RUN npx hardhat compile

# Expose the default Hardhat node port
EXPOSE 8545

# Create a script to run Hardhat node with proper configuration
RUN echo '#!/bin/sh' > /app/start-node.sh && \
    echo 'npx hardhat node --hostname 0.0.0.0 --port 8545' >> /app/start-node.sh && \
    chmod +x /app/start-node.sh

# Set the default command to run Hardhat node
CMD ["/app/start-node.sh"]