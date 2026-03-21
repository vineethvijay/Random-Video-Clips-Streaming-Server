# Gunicorn config: start clip_pusher in the worker after fork.
# With --preload, the app is loaded in the master; the push loop must run in the
# worker so /api/status and the RTMP push share the same process state.
def post_fork(server, worker):
    from app import clip_pusher
    clip_pusher.start()

bind = "0.0.0.0:8080"
worker_class = "gthread"
threads = 2
workers = 1
preload = True
timeout = 120
accesslog = "-"
errorlog = "-"
