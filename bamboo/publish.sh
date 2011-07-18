#!/bin/bash

if [[ `hostname` == 'bldzone2.joyent.us' ]] ; then 
    ssh bamboo@10.2.0.190 mkdir -p $PUBLISH_LOCATION
    ssh bamboo@10.2.0.190 mkdir -p $ASSETS_LOCATION
    scp build/pkg/cabase.tar.gz    "bamboo@10.2.0.190:$PUBLISH_LOCATION/$CABASE_PKG"
    scp build/pkg/cainstsvc.tar.gz "bamboo@10.2.0.190:$PUBLISH_LOCATION/$CAINSTSVC_PKG"
    scp build/dist/$CA_PKG "bamboo@10.2.0.190:$ASSETS_LOCATION/$CA_PKG"
else
    pfexec mkdir -p $PUBLISH_LOCATION
    pfexec mkdir -p $ASSETS_LOCATION
    pfexec cp build/pkg/cabase.tar.gz    $PUBLISH_LOCATION/$CABASE_PKG
    pfexec cp build/pkg/cainstsvc.tar.gz $PUBLISH_LOCATION/$CAINSTSVC_PKG
    pfexec cp build/dist/$CA_PKG $ASSETS_LOCATION/$CA_PKG
fi
