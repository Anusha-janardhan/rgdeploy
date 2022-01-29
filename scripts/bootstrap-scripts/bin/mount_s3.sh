#!/usr/bin/env bash

# This script mounts S3 buckets/prefixes onto the local filesystem using fuse and
#   goofys. It also attempts to create a sym link to the mounted data if the instance
#   is an EMR or SageMaker instance so that it can be easily accessed by Jupyter notebooks.
#
# /usr/local/s3-mounts.json should contain S3 study data metadata of the form
#  [{
#   "id": "STUDY_ID",
#   "bucket": "BUCKET_NAME",
#   "prefix": "BUCKET_PREFIX"
# }, ...]
CONFIG="/usr/local/etc/s3-mounts.json"
MOUNT_DIR="${HOME}/studies"
AWS_CONFIG_DIR="${HOME}/.aws"

# Exit if CONFIG doesn't exist or is 0 bytes
[ ! -s "$CONFIG" ] && exit 0

# Add roleArn for a study to credentials file if not present already
append_role_to_credentials() {
    study_id=$1
    role_arn=$2
    credentials_file=$AWS_CONFIG_DIR/credentials
    if ! grep -q "\[$study_id\]" $AWS_CONFIG_DIR/credentials &>/dev/null
    then
      # append role for this study since it doesn't already exist in the file
      echo "[$study_id]" >> $credentials_file
      echo "role_arn = $role_arn" >> $credentials_file
      echo "credential_source = Ec2InstanceMetadata" >> $credentials_file
      echo "" >> $credentials_file
    fi
}

# Mount S3 buckets
mounts="$(cat "$CONFIG")"
num_mounts=$(printf "%s" "$mounts" | jq ". | length" -)
for ((study_idx=0; study_idx<$num_mounts; study_idx++))
do
    # Parse bucket/key info
    study_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].id" -)"
    s3_bucket="$(printf "%s" "$mounts" | jq -r ".[$study_idx].bucket" -)"
    s3_prefix="$(printf "%s" "$mounts" | jq -r ".[$study_idx].prefix" -)"
    s3_role_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].roleArn" -)"
    kms_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].kmsArn" -)"

    # Mount S3 location if not already mounted
    study_dir="${MOUNT_DIR}/${study_id}"
    ps -U "$LOGNAME" -o "command" | egrep -q "goofys .* ${study_dir}$"
    if [ $? -ne 0 ]
    then
        mkdir -p "$study_dir"
        if [ "$s3_role_arn" == "null" ]
        then
            printf 'Mounting internal study "%s" at "%s"\n' "$study_id" "$study_dir"
            goofys --acl "bucket-owner-full-control" "${s3_bucket}:${s3_prefix}" "$study_dir"
        else
            # make .aws dir if it doesn't already exist and add credentials
            mkdir -p $AWS_CONFIG_DIR
            append_role_to_credentials $study_id $s3_role_arn
            if [ "$kms_arn" == "null" ]
            then
                printf 'Mounting external study "%s" at "%s" using role "%s" \n' "$study_id" "$study_dir" \
                "$s3_role_arn"
                goofys --profile $study_id --acl "bucket-owner-full-control" \
                "${s3_bucket}:${s3_prefix}" "$study_dir"
            else
                printf 'Mounting external study "%s" at "%s" using role "%s" and kms arn "%s" \n' "$study_id" "$study_dir" \
                "$s3_role_arn" "$kms_arn"
                goofys --profile $study_id --sse-kms $kms_arn --acl "bucket-owner-full-control" \
                "${s3_bucket}:${s3_prefix}" "$study_dir"
            fi
        fi
    fi
done
