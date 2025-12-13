FROM alpine

# Install necessary dependencies:
# - bash: The script is written for bash
# - docker: To interact with the host's Docker daemon
# - docker-compose: For the 'docker compose' (v2) command
# - bc: For floating-point arithmetic used in the script
RUN apk add --no-cache \
    bash \
    docker \
    docker-compose \
    bc

# Copy the autoscaler script
COPY docker-autoscale.sh /usr/local/bin/docker-autoscale.sh

# Make the script executable
RUN chmod +x /usr/local/bin/docker-autoscale.sh

WORKDIR /app

# Set the entrypoint to the script.
# Arguments passed to `docker run` or `command` in docker-compose will be appended to this.
ENTRYPOINT ["/usr/local/bin/docker-autoscale.sh"]

# Provide a default command to show the help message if no arguments are given.
CMD ["--help"]
