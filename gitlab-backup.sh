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
    echo "\t-p(or --prometheus_pushgateway_url)=prometheus_pushgateway_url (reports metrics backup)"
    echo "\-s(or --sre_team)=sre_team (sret1 or sret2, etc..)"
    echo "\-l(or --line)=line (production, staging, dev, int, ...)"
    echo "\-\-skip skip a backup unit, check https://docs.gitlab.com/ee/raketasks/backup_restore.html#excluding-specific-directories-from-the-backup"
    echo ""
}
LINE='prod'

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        -p | --prometheus_pushgateway_url)
            PROMETHEUS_PUSHGATEWAY_URL=$VALUE
            ;;
        -s | --sre_team)
           SRE_TEAM=$VALUE
           ;;
        -l | --line)
          LINE=$VALUE
          ;;
        --skip)
          SKIP=$VALUE
          ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 0
            ;;
    esac
    shift
done




if [ -z "$SRE_TEAM" ]; then
 echo "please define sre team paramete example -s=sret1"
fi

export POD=$(oc get pod  -o jsonpath='{.items.*.metadata.name}' | sed 's/ /\n/g' | grep 'gitlab-task-runner-') || exit 0
if [[ "$SKIP" == "" ]];then
export OUTPUT=$(oc exec $POD -i "backup-utility")
else
echo "SKIPPING $SKIP"
export OUTPUT=$(oc exec $POD -i "backup-utility --skip $SKIP")
fi
export RESULT=$?
if [ -z "$PROMETHEUS_PUSHGATEWAY_URL" ]; then
    echo "$OUTPUT" || exit 0
    exit 0
else
    export H=$(oc exec $POD -i "hostname") || exit 0
    export OS=$(oc exec $POD -it "cat" "/etc/os-release" ) || exit 0
    export OS=$(echo "$OS" | grep -e "^NAME=" | sed 's/NAME=//g' | sed 's/"//g')
    export METRICS=$(
        #define the type of metric
        #for every repo we have a metric indicating backup success
        echo "#TYPE gitlab_backup_repo gauge";
        echo "$OUTPUT" |
        # awk is your friend to transform the output into prometheus metrics
        awk -v h="$POD" -v ostype="$OS" -v sre_team="$SRE_TEAM"  -v line="$LINE" '/ .*\[.*\]/{
        gsub("Dumping","");
        gsub("\\\[DONE\\\]",0);
        gsub("\\\[SKIPPED\\\]",1);
        gsub("\\\[WARNING\\\]",2);
        gsub("\\\[ERROR\\\]",3);
        gsub("\\\[.*\\\]",4);
        gsub(" \\\* ","");
        gsub("/","-");
        gsub("-","_");
        printf "gitlab_backup_repo {repo=\"%s\",certname=\"%s\",os=\"%s\",project=\"gitlab_backup\",line=\"%s\",sre_team=\"%s\"} %d\n",$1,h,ostype,line,sre_team, $NF;
        }';
        # finaly the global sucess of the backup
        echo -e "#TYPE gitlab_backup_success gauge"
        echo -e "gitlab_backup_success{certname=\"$H\",os=\"$OS\", project=\"gitlab_backup\",line=\"$LINE\",sre_team=\"$SRE_TEAM\"} $RESULT") || exit 0

    # lets push the metrics to the gateway
    echo -e "$METRICS" | curl --data-binary @- $PROMETHEUS_PUSHGATEWAY_URL || exit 0
    # never fail, because failure is bad
    echo -e "output:\n$OUTPUT"
    echo -e "metric:\n$METRICS"
    echo -e "result:\n$RESULT"
    exit 0
fi
