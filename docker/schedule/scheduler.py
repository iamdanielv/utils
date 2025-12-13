import argparse
import logging
import sched
import select
import subprocess
import signal
import time
from datetime import datetime

import yaml
from croniter import croniter

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)


def run_task(service_name: str, project_name: str):
    """Runs a one-off container for the given service and logs its output."""
    command = [
        "docker",
        "compose",
        "-p",
        project_name,
        "run",
        "--rm",
        service_name,
    ]
    try:
        def service_log_line(line: str, is_exit_code: bool = False):
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            end_char = "\n" if is_exit_code else ""
            print(f"[{service_name}] [{timestamp}] {line}", end=end_char, flush=True)
        service_log_line("Starting task...\n")
        # Use Popen to stream output in real-time
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

        # Use select to read from stdout and stderr as data becomes available
        while process.poll() is None:
            reads = [process.stdout.fileno(), process.stderr.fileno()]
            ret = select.select(reads, [], [])

            for fd in ret[0]:
                if fd == process.stdout.fileno():
                    line = process.stdout.readline()
                    if line:
                        service_log_line(line)
                if fd == process.stderr.fileno():
                    line = process.stderr.readline()
                    if line:
                        service_log_line(line)

        # Capture any remaining output
        for line in process.stdout:
            service_log_line(line)
        for line in process.stderr:
            service_log_line(line)

        service_log_line(f"EXIT CODE - {process.returncode}", is_exit_code=True)

    except FileNotFoundError:
        logging.error("`docker` command not found. Is the Docker CLI installed in the container and in PATH?")
    except Exception as e:
        logging.error(f"An error occurred while running task for {service_name}: {e}")


def schedule_tasks(compose_file: str, project_name: str):
    """Schedules tasks based on labels in the docker-compose file."""
    scheduler = sched.scheduler(time.time, time.sleep)

    with open(compose_file, "r") as f:
        compose_config = yaml.safe_load(f)

    services = compose_config.get("services", {})
    for service_name, config in services.items():
        labels_raw = config.get("labels", {})
        labels_dict = {}
        if isinstance(labels_raw, list):
            # Handle labels as a list of "key=value" strings
            for label in labels_raw:
                if "=" in label:
                    key, value = label.split("=", 1)
                    labels_dict[key] = value
        elif isinstance(labels_raw, dict):
            # Handle labels as a dictionary
            labels_dict = labels_raw

        cron_str = labels_dict.get("scheduler.cron")
        interval_str = labels_dict.get("scheduler.interval")

        if cron_str:
            if not croniter.is_valid(cron_str):
                logging.error(f"Invalid cron expression '{cron_str}' for service '{service_name}'. Skipping.")
                continue

            logging.info(f"Scheduling service '{service_name}' with cron expression: '{cron_str}'")

            def periodic_cron_runner(s_name=service_name, c_str=cron_str):
                try:
                    run_task(s_name, project_name)
                except Exception as e:
                    logging.error(f"Unhandled exception in task runner for '{s_name}': {e}")
                finally:
                    # Always reschedule for the next time
                    now = time.time()
                    itr = croniter(c_str, now)
                    next_run = itr.get_next(float)
                    delay = max(0, next_run - now)
                    scheduler.enter(delay, 1, periodic_cron_runner)

            # Calculate the first run
            now = time.time()
            itr = croniter(cron_str, now)
            scheduler.enter(max(0, itr.get_next(float) - now), 1, periodic_cron_runner)

        elif interval_str:
            try:
                interval = int(interval_str)
                if interval <= 0:
                    logging.error(f"Interval for service '{service_name}' must be positive. Got '{interval_str}'. Skipping.")
                    continue
            except ValueError:
                logging.error(f"Invalid interval '{interval_str}' for service '{service_name}'. Must be an integer. Skipping.")
                continue

            logging.info(f"Scheduling service '{service_name}' to run every {interval} seconds.")

            def periodic_interval_runner(s_name=service_name, scheduled_time=time.time()):
                try:
                    run_task(s_name, project_name)
                except Exception as e:
                    logging.error(f"Unhandled exception in task runner for '{s_name}': {e}")
                finally:
                    next_run_time = scheduled_time + interval
                    delay = max(0, next_run_time - time.time())
                    scheduler.enter(delay, 1, periodic_interval_runner, kwargs={"scheduled_time": next_run_time})
            scheduler.enter(0, 1, periodic_interval_runner)  # Start immediately

    if not scheduler.empty():
        scheduler.run()
    else:
        logging.info("No services with 'scheduler.interval' label found. Exiting.")


def shutdown_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    logging.info(f"Signal {signum} received. Shutting down scheduler...")
    # The script will exit after the current running task (if any) completes.
    # The `sched` loop will not continue.
    exit(0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="A simple docker-compose task scheduler.")
    parser.add_argument("--compose-file", default="/app/docker-compose.yml", help="Path to docker-compose.yml")
    parser.add_argument("--project-name", required=True, help="Docker compose project name")
    args = parser.parse_args()

    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)

    schedule_tasks(args.compose_file, args.project_name)