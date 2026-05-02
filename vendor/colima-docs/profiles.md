# Profiles

A profile is an independent Colima VM instance with its own config, runtime, and data.

## Creating Profiles

```bash
colima start dev
colima start dev --cpus 4 --memory 8
colima start k8s --kubernetes
```

## Listing

```bash
colima list
```

## Start / Stop / Restart / Delete

```bash
colima start dev
colima stop dev
colima restart dev
colima delete dev           # soft delete, preserves data
colima delete dev --data    # hard delete, removes everything
colima delete dev --data --force
```

## Specifying a Profile

1. As argument: `colima start dev`
2. As flag: `colima start --profile dev`
3. Environment variable: `export COLIMA_PROFILE=dev`

Priority: `--profile` flag > argument > `COLIMA_PROFILE` > default.

## Environment Variables

- `COLIMA_HOME` — Base directory (default: ~/.colima)
- `COLIMA_PROFILE` — Active profile (default: default)
- `DOCKER_CONFIG` — Docker client config (default: ~/.docker)

## Docker Context with Profiles

```bash
docker context ls
docker context use colima-dev
```
