#!/usr/bin/env bash

vagrant ssh ydb-node-1 -c "export LD_LIBRARY_PATH=/opt/ydb/lib && /opt/ydb/bin/ydbd admin blobstorage config init --yaml-file  /opt/ydb/cfg/config.yaml"
