# docker-ff

## Notes

### Celery command

```bash
celery -A flaskfarm.main.celery --workdir=/data \
    worker --concurrency=2 --loglevel=info --pool=gevent \
        --config_filepath=/data/config.yaml --running_type=docker \
        --without-gossip --without-mingle --without-heartbeat
```

### Environment Variables

Following ENVs are directly passed and recognized by FF

```bash
REDIS_PORT
UPDATE_STOP
PLUGIN_UPDATE_FROM_PYTHON
RUNNING_TYPE
```

## Handling Warnings

### vm.overcommit_memory

```bash
# WARNING overcommit_memory is set to 0! Background save may fail under low memory condition. To fix this issue add 'vm.overcommit_memory = 1' to /etc/sysctl.conf and then reboot or run the command 'sysctl vm.overcommit_memory=1' for this to take effect.
```

### Transparent Huge Pages (THP)

```bash
# WARNING you have Transparent Huge Pages (THP) support enabled in your kernel. This will create latency and memory usage issues with Redis. To fix this issue run the command 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' as root, and add it to your /etc/rc.local in order to retain the setting after a reboot. Redis must be restarted after THP is disabled.
```

add followings to crontab, then reboot

```bash
@reboot echo never > /sys/kernel/mm/transparent_hugepage/enabled
@reboot echo never > /sys/kernel/mm/transparent_hugepage/defrag
```
