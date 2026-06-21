# SeaweedFS — S3-Compatible Object Storage

Image: `chrislusf/seaweedfs:4.33_full`

## Fungsi

Distributed object storage dengan S3-compatible API.
Primary object storage untuk GitLab (artifacts, LFS, registry, uploads).
Tersedia untuk project development via S3 endpoint.

## Endpoint

- S3 API: `https://s3.dts.system` (via Traefik)
- S3 API internal: `http://seaweedfs:8333` (dari container di infra-backend-net)

## Port Internal

| Port | Fungsi |
|---|---|
| 9333 | Master API (health check, cluster status) |
| 8080 | Volume Server |
| 8888 | Filer API |
| 8333 | S3 API Gateway |

## S3 Buckets GitLab

Dibuat saat post-deploy:

```bash
source _shared/.env
for bucket in gitlab-artifacts gitlab-lfs gitlab-registry gitlab-uploads \
              gitlab-packages gitlab-backups gitlab-tmp; do
    aws s3 mb "s3://${bucket}" --endpoint-url http://localhost:8333
done
```

## Menggunakan S3 dari Project Development

```python
import boto3
s3 = boto3.client('s3',
    endpoint_url='https://s3.dts.system',
    aws_access_key_id='YOUR_ACCESS_KEY',
    aws_secret_access_key='YOUR_SECRET_KEY',
    region_name='us-east-1'
)
```
