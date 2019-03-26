#!/bin/bash
docker build --rm -f "Dockerfile" -t docker-gitlab-openshift-backup:latest .
docker run -it docker-gitlab-openshift-backup:latest /bin/bash