FROM python:3.13-slim

WORKDIR /app

# Install system dependencies for audio processing
RUN apt-get update && apt-get install -y \
    libsndfile1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy agent code
COPY agent.py .
COPY livekit.toml .

# Expose HTTP health check port (LiveKit Agents SDK auto-starts HTTP server)
EXPOSE 8080

# Run the agent in production mode
CMD ["python", "agent.py", "start"]
