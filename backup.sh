#!/bin/bash

shopt -s dotglob # Show Hidden Files

#-----------------------------
# IMPORTANT NOTES
# 1. While Creating .conf file add an empty line at end of file.
# 2. SSH Key access to Backup Server
#-----------------------------

#-----------------------------
# VARIABLES
#-----------------------------
PKEY=id_rsa
FILES=./.*.conf
THEDATE=`date +%d%m%y%H%M`
VARS=(THESITE THEDBTYPE THEDB THEDBUSER THEDBPW THEDBPORT THEHOST THEUSER) # Make sure your conf file have the same order
KEEPDAYS=7
BACKUP_DIR=files
SUBJECT="🗄️ Backup Reports | Date: $THEDATE";
SENDGRID_API_KEY=""
EMAIL_TO=""
FROM_EMAIL=""
FROM_NAME="Backup Server"

#-----------------------------
# LOOPING THROUGH CONF FILES
#-----------------------------
for file in $FILES
do
    echo "Reading From File : ${file}"
    COUNTER=0
    while read line
    do
        if [ "$line" != "" ]
        then
            new_var=${VARS[$COUNTER]}
            declare ${VARS[$COUNTER]}="$line"
            echo "Setting Variables..."
            COUNTER=$[$COUNTER +1]
        fi
    done <<< "$(cat "${file}")"

    #-----------------------------
    # CREATE SITE BACKUP DIR IF NOT EXISTS
    #-----------------------------
    if [ ! -d $BACKUP_DIR/$THESITE ]
    then
        mkdir -p $BACKUP_DIR/$THESITE
    fi

    #-----------------------------
    # START DB BACKUP
    #-----------------------------
    if [ "$THEDBTYPE" = "mysql" ]; then
        FILENAME=$THEDBTYPE-$THEDB.$THEDATE.sql.gz # Set the backup filename
        THEDBPORT="${THEDBPORT:-3306}"
        echo "Connecting to $THEHOST@$THEUSER .."
        echo "Backing up $THEDB .."

        # Dump the MySQL and gzip it up
        ssh -i $PKEY $THEUSER@$THEHOST "mysqldump -q -u'$THEDBUSER' -P $THEDBPORT -p'$THEDBPW' $THEDB | gzip -9 > $FILENAME"
    fi

    if [ "$THEDBTYPE" = "mongo" ]; then
        FILENAME=$THEDBTYPE-$THEDB.$THEDATE.tgz # Set the backup filename
        THEDBPORT="${THEDBPORT:-22017}"
        echo "Connecting to $THEHOST@$THEUSER .."
        echo "Backing up $THEDB .."

        # Dump the Mongo and gzip it up
        ssh -i $PKEY $THEUSER@$THEHOST "mongodump --port=$THEDBPORT -d $THEDB -u $THEDBUSER -p '$THEDBPW' --authenticationDatabase=admin --gzip -o backmon && tar -cvzf $FILENAME backmon/$INPUT_DB_NAME"
    fi

    echo "🔄 Syncing from $THEHOST@$THEUSER the $THEDBTYPE backups to our server.."
    sh -c "rsync --remove-source-files -avzhe 'ssh -i $PKEY -o StrictHostKeyChecking=no' --progress $THEUSER@$THEHOST:./$THEDBTYPE* $BACKUP_DIR/$THESITE/"

    echo "🤔 Whats the location of backups..."
    echo $BACKUP_DIR/$THESITE
    
    echo "🔍 Show me backups... 😎"
    ls -lFhS $BACKUP_DIR/$THESITE

    echo "Removing Old Backups..."
    find $BACKUP_DIR/$THESITE -type f -mtime +$KEEPDAYS -name '*.gz' -execdir rm -- '{}' \;
    echo "Done .."
done

#-----------------------------
# EMAIL THE REPORTS
#-----------------------------
if [ ! -z "$SENDGRID_API_KEY" ] && [ "$SENDGRID_API_KEY" != "" ]; then
    REPORTS=$(base64 reports.txt)
    REQUEST_DATA='{
        "personalizations": [{ 
            "to": [{ "email": "'"$EMAIL_TO"'" }],
        }],
        "subject": "'"$SUBJECT"'",
        "from": {
            "email": "'"$FROM_EMAIL"'",
            "name": "'"$FROM_NAME"'" 
        },
        "content": [{
            "type": "text/html",
            "value": "Team, <br><br> Here are the logs🗒 of backup script for today, Hope everything is okay and you have a nice day 🎉😁<br><br>Regards,<br>Backup Bot🤖"
        }],
        "attachments": [{
            "content": "'"$REPORTS"'",
            "type": "text/plain",
            "filename": "reports.txt"
        }]
    }';

    curl -X "POST" "https://api.sendgrid.com/v3/mail/send" \
        -H "Authorization: Bearer $SENDGRID_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$REQUEST_DATA"
fi

shopt -u dotglob # Hide Hidden Files
