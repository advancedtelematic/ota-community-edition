# ota-treehub

## Config options

Treehub can use local storage or S3 as a backend. The chart uses local storage by default.

To use S3, set `configMap.TREEHUB_STORAGE: s3` in `values.yaml`. Then add the AWS credentials by editing the following keys in `values.yaml`:

```
secret:
  TREEHUB_AWS_ACCESS_KEY:
  TREEHUB_AWS_SECRET_KEY:
```
