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
    echo "./.sh"
    echo "\t-h --help"
    echo "\t--environment=$ENVIRONMENT"
    echo "\t--db-path=$DB_PATH"
    echo ""
}

oc exec $(oc get pod  -o jsonpath='{.items.*.metadata.name}' | sed 's/ /\n/g' | grep 'gitlab-task-runner-') -it '
              output=$(backup-utility);
              RESULT=$?;
              METRICS=$(
              echo "#TYPE gitlab_backup_repo gauge";
              echo "$output" | 
              awk -v "h=$HOSTNAME" -v "ostype=$OSTYPE"  '"'"'/ .*\[.*\]/{
              gsub("Dumping","");
              gsub("\[DONE\]",0);
              gsub("\[SKIPPED\]",1);
              gsub("\[WARNING\]",2);
              gsub("\[ERROR\]",3);
              gsub("\[.*\]",4);
              gsub(" \* ","");
              gsub("/","-");
              gsub("-","_");
              printf "gitlab_backup_repo {repo=\"" $1 "\",certname=\"%s\",os=\"%s\",project=\"chtopo_gitlab_backup\",line=\"production\",sre_team=\"sret1\"} %d\n",h,ostype, $NF;
              }'"'"'; echo -e "#TYPE gitlab_backup_success gauge\ngitlab_backup_success{certname=\"$HOSTNAME\",os=\"$OSTYPE\",project=\"chtopo_gitlab_backup\",line=\"production\",sre_team=\"sret1\"} $RESULT\n");
              echo -e "$METRICS" | curl --data-binary @- http://infra-metrics-prometheus-pushgateway.infra-metrics.svc:9091/metrics/job/gitlab-backup
              ' || exit 0
          restartPolicy: Never
