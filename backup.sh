#!/bin/bash
#
# Argument = -u user -p password -k key -s secret -b bucket
#
# To Do - Add logging of output.
# To Do - Abstract bucket region to options

set -e

export PATH="$PATH:/usr/local/bin:/var/lib/mongodb-mms-automation/bin"

usage()
{
cat << EOF
usage: $0 options

This script dumps the current mongo database, tars it, then sends it to an Amazon S3 bucket.

OPTIONS:
   -h      Show this message
   -u      Mongodb user
   -p      Mongodb password
   -k      AWS Access Key
   -s      AWS Secret Key
   -r      Amazon S3 region
   -b      Amazon S3 bucket name
EOF
}

MONGODB_USER=
MONGODB_PASSWORD=
AWS_ACCESS_KEY=
AWS_SECRET_KEY=
S3_REGION=
S3_BUCKET=
CMD_OPTS=
HOSTNAME=`hostname -f`
BACKUP_PATH="backup"

while getopts “h:u:p:k:s:r:b:” OPTION
do
  case $OPTION in
    h)
      MONGODB_HOST=$OPTARG
      ;;
    u)
      MONGODB_USER=$OPTARG
      ;;
    p)
      MONGODB_PASSWORD=$OPTARG
      ;;
    k)
      AWS_ACCESS_KEY=$OPTARG
      ;;
    s)
      AWS_SECRET_KEY=$OPTARG
      ;;
    r)
      S3_REGION=$OPTARG
      ;;
    b)
      S3_BUCKET=$OPTARG
      ;;
    ?)
      usage
      exit
    ;;
  esac
done

if [[ -z $AWS_ACCESS_KEY ]] || [[ -z $AWS_SECRET_KEY ]] || [[ -z $S3_BUCKET ]]
then
  usage
  exit 1
fi

if [[ -z $MONGODB_HOST ]]
then
  MONGODB_HOST="localhost"
fi

if [[ -z $S3_REGION ]]
then
  S3_REGION="us-east-1"
fi

# Get the directory the script is being run from
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Store the current date in YYYY-mm-DD-HHMMSS
DATE=$(date -u "+%F-%H%M%S")
FILE_NAME="backup-$DATE"
ARCHIVE_NAME="$FILE_NAME.tar.gz"
CMD_OPTS="--host $MONGODB_HOST"
echo "ARCHIVE_NAME: $ARCHIVE_NAME"

# create local backup path
mkdir -p $DIR/$BACKUP_PATH

if [ $MONGODB_USER ]
then
  CMD_OPTS="$CMD_OPTS -username $MONGODB_USER"
fi

if [ $MONGODB_PASSWORD ]
then
  CMD_OPTS="$CMD_OPTS -password $MONGODB_PASSWORD"
fi
echo "output path for mongodump: $DIR/$BACKUP_PATH/$FILE_NAME"

# Dump the database
mongodump $CMD_OPTS -o $DIR/$BACKUP_PATH/$FILE_NAME

# Tar Gzip the file
tar -C $DIR/$BACKUP_PATH/ -zcvf $DIR/$BACKUP_PATH/$ARCHIVE_NAME $FILE_NAME/
echo "compressing file to: $DIR/$BACKUP_PATH/$ARCHIVE_NAME"

# Remove the backup directory
rm -r $DIR/$BACKUP_PATH/$FILE_NAME

# Send the file to the backup drive or S3
HEADER_DATE=$(date -u "+%a, %d %b %Y %T %z")
CONTENT_MD5=$(openssl dgst -md5 -binary $DIR/$BACKUP_PATH/$ARCHIVE_NAME | openssl enc -base64)
CONTENT_TYPE="application/x-download"
STRING_TO_SIGN="PUT\n$CONTENT_MD5\n$CONTENT_TYPE\n$HEADER_DATE\n/$S3_BUCKET/$HOSTNAME/$ARCHIVE_NAME"
SIGNATURE=$(echo -e -n $STRING_TO_SIGN | openssl dgst -sha1 -binary -hmac $AWS_SECRET_KEY | openssl enc -base64)

echo "uploading backup to s3..."
curl -X PUT \
--header "Host: $S3_BUCKET.s3.amazonaws.com" \
--header "Date: $HEADER_DATE" \
--header "content-type: $CONTENT_TYPE" \
--header "Content-MD5: $CONTENT_MD5" \
--header "Authorization: AWS $AWS_ACCESS_KEY:$SIGNATURE" \
--upload-file $DIR/backup/$ARCHIVE_NAME \
https://$S3_BUCKET.s3.amazonaws.com/$HOSTNAME/$ARCHIVE_NAME

# Remove the archive
echo "cleaning up..."
rm -r $DIR/$BACKUP_PATH
echo "upload to s3 complete."
