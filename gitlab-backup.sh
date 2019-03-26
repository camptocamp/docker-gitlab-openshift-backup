#!/bin/bash 

###################################################################
#Script Name    : finds the gitlab task runner, intiate a backup
#                 and report metrics to a prometheus pushgateway
#Description    :                                                                                 
#Args           :                                                                                           
#Author         : Max Laager                                                
#Email          : max.laager@camptocamp.com                                           
###################################################################

function usage()
{
    echo "git lab backup for openshif:"
    echo "this intial the gitlab bakcup, using task runner from gitlab helm chart"
    echo "./gitlab-backup.sh"
    echo "\t-h --help"
    echo "\t-p=prometheus_pushgateway_url (reports metrics backup)"
    echo "\-s=sre_team (sret1 or sret2, etc..)"
    echo "\t--db-path=$DB_PATH"
    echo ""
}

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        -p)
            PROMETHEUS_PUSHGATEWAY_URL=$VALUE
            ;;
        -s)
           SRE_TEAM=$VALUE
           ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$SRE_TEAM" ]; then
 echo "please define sre team paramete example -s=sret1"
fi

if [ -z "$PROMETHEUS_PUSHGATEWAY_URL" ]; then
 CMD='backup-utility'
else
    CMD=$(cat <<-EOF
    # execute the backup and capture the output
    output=\$(backup-utility);
    # caputre the backup success result
    RESULT=\$?;
    # use awk to tranform logs into metric... 
    # todo scrape all this and do with ELK....
    METRICS=\$(
    #define the type of metric 
    #for every repo we have a metric indicating backup success
    echo "#TYPE gitlab_backup_repo gauge";
    echo "\$output" | 
    # awk is your friend to transform with into prometheus metrics
    awk -v h="\$HOSTNAME" -v ostype="\$OSTYPE"  '/ .*\[.*\]/{
    gsub("Dumping","");
    gsub("\[DONE\]",0);
    gsub("\[SKIPPED\]",1);
    gsub("\[WARNING\]",2);
    gsub("\[ERROR\]",3);
    gsub("\[.*\]",4);
    gsub(" \* ","");
    gsub("/","-");
    gsub("-","_");
    printf "gitlab_backup_repo {repo=\"" \$1 "\",certname=\"%s\",os=\"%s\",
    project=\"chtopo_gitlab_backup\",line=\"production\",sre_team=\"$SRE_TEAM\"} %d\n",h,ostype, \$NF;
    }'; 
    # finaly the global sucess of the backup
    echo -e "#TYPE gitlab_backup_success gauge\ngitlab_backup_success{certname=\"\$HOSTNAME\",os=\"\$OSTYPE\",
    project=\"chtopo_gitlab_backup\",line=\"production\",sre_team=\"$SRE_TEAM\"} \$RESULT\n");
    echo -e "\$METRICS" | curl --data-binary @- $PROMETHEUS_PUSHGATEWAY_URL
EOF
)
fi

POD=$(oc get pod  -o jsonpath='{.items.*.metadata.name}' | sed 's/ /\n/g' | grep 'gitlab-task-runner-') 
echo $CMD
oc exec $POD -it "'""$CMD""'" || exit 0