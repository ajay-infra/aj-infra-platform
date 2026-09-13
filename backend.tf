terraform {
  # Partial backend on purpose: bucket, key, region and the S3 lockfile arrive
  # from ajtf at init (aj-infra-context/arch/ajtf-v1.md §2) — nothing is typed here.
  backend "s3" {}
}
