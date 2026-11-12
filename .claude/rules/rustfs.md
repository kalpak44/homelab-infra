# Rules – RustFS buckets and access

RustFS (`rustfs-lxc`, 192.168.1.13) is the homelab's S3 store. When a bucket, an access key or a
permission is needed, make it with `mc` against the `homelab` alias from this machine — not in the
console, and not as Terraform.

## Connect

```bash
mc alias set homelab https://rustfs.internal.pavel-usanli.online \
  "$(vault kv get -field=access-key secret/rustfs-secrets)" \
  "$(vault kv get -field=secret-key secret/rustfs-secrets)"
mc admin info homelab
```

Recreate the alias whenever `mc admin info homelab` fails to authenticate; the root keys live only
in Vault, so a rotated key there is the usual cause.

## Giving an app a bucket

1. `mc mb homelab/<bucket>` — lowercase, named for what it holds, not who uses it.
2. A policy scoped to that bucket alone, named `<bucket>-rw` or `<bucket>-ro`:
   `mc admin policy create homelab <bucket>-rw <file>` with `Resource` set to
   `arn:aws:s3:::<bucket>` and `arn:aws:s3:::<bucket>/*`.
3. A user per app, with that policy attached:
   `mc admin user add homelab <app> <random>` and
   `mc admin policy attach homelab <bucket>-rw --user <app>`.
4. The app's keys go straight into Vault as `secret/<app>-secrets` with keys `access-key` and
   `secret-key` — see `secrets.md`. Never print them into the conversation, a file, or a commit.

**Never hand an app the root keys.** They can delete every bucket and user; a per-app user caps the
damage to the one bucket it owns.

## Things to know

- **Path-style only.** There is no wildcard DNS for `<bucket>.rustfs.internal…`, so clients need
  `force_path_style` / `addressing_style: path`. The region is `us-east-1`.
- **Check the volume before a large bucket.** `/data` is 100G; the `rustfs` host dashboard in
  Grafana shows what is left. Grow it in `terraform/proxmox/rustfs-lxc/main.tf`, never by deleting
  someone else's objects.
- **Anonymous access is opt-in per bucket** (`mc anonymous set download`). Do it only when asked,
  and only on a bucket that holds nothing else.
- `mc` is archived upstream with MinIO and still speaks RustFS's API. If it stops working, RustFS's
  own `rc` (`rustfs/cli`) is the maintained replacement.
