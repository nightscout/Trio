FROM node:22-slim

# Install Python3 + Pillow for FatSecret image analysis script
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-pip python3-pil && \
    rm -rf /var/lib/apt/lists/*

# Install OpenClaw globally
RUN npm install -g openclaw@latest

# Create workspace directory
WORKDIR /app/workspace

# Copy workspace config and skills
COPY openclaw.json .
COPY skills/ skills/

# OpenClaw stores session data in ~/.openclaw
VOLUME ["/root/.openclaw"]

# Gateway default port
EXPOSE 18789

# Start the gateway
CMD ["openclaw", "gateway", "run"]
