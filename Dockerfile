FROM python:3.11-slim

# Install ffmpeg, curl (for healthcheck), and required system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user for security
RUN useradd -m -u 1000 appuser \
    && chown -R appuser:appuser /app

# Expose port
EXPOSE 8080

# Set Python to unbuffered mode for logs
ENV PYTHONUNBUFFERED=1

# Switch to non-root user
USER appuser

# Run with gunicorn; post_fork in gunicorn.conf.py starts the clip_pusher in the worker
CMD ["gunicorn", "-c", "gunicorn.conf.py", "app:app"]
