#!/usr/bin/env bash
sudo apt update 
sudo apt -y install parted curl
sudo groupadd ydb 
sudo useradd ydb -g ydb
sudo usermod -aG disk ydb
sudo parted /dev/sda mklabel gpt -s
sudo parted -a optimal /dev/sda mkpart primary 0% 100%
sudo parted /dev/sda name 1 ydb_disk_ssd_01
sudo partx --u /dev/sda
sudo parted /dev/sdb mklabel gpt -s
sudo parted -a optimal /dev/sdb mkpart primary 0% 100%
sudo parted /dev/sdb name 1 ydb_disk_ssd_02
sudo partx --u /dev/sdb
sudo parted /dev/sdc mklabel gpt -s
sudo parted -a optimal /dev/sdc mkpart primary 0% 100%
sudo parted /dev/sdc name 1 ydb_disk_ssd_03
sudo partx --u /dev/sdc
mkdir ydbd-stable-linux-amd64
curl -L https://binaries.ydb.tech/release/22.4.44/ydbd-22.4.44-linux-amd64.tar.gz | tar -xz --strip-component=1 -C ydbd-stable-linux-amd64
sudo mkdir -p /opt/ydb /opt/ydb/cfg
sudo chown -R ydb:ydb /opt/ydb
sudo cp -iR ydbd-stable-linux-amd64/bin /opt/ydb/
sudo cp -iR ydbd-stable-linux-amd64/lib /opt/ydb/
sudo LD_LIBRARY_PATH=/opt/ydb/lib /opt/ydb/bin/ydbd admin bs disk obliterate /dev/disk/by-partlabel/ydb_disk_ssd_01
sudo LD_LIBRARY_PATH=/opt/ydb/lib /opt/ydb/bin/ydbd admin bs disk obliterate /dev/disk/by-partlabel/ydb_disk_ssd_02
sudo LD_LIBRARY_PATH=/opt/ydb/lib /opt/ydb/bin/ydbd admin bs disk obliterate /dev/disk/by-partlabel/ydb_disk_ssd_03

sudo cat <<'EOF' >> /etc/systemd/system/ydbd-storage.service
[Unit]
Description=YDB storage node
After=network-online.target rc-local.service
Wants=network-online.target
StartLimitInterval=10
StartLimitBurst=15

[Service]
Restart=always
RestartSec=1
User=ydb
PermissionsStartOnly=true
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=ydbd
SyslogFacility=daemon
SyslogLevel=err
Environment=LD_LIBRARY_PATH=/opt/ydb/lib
ExecStart=/opt/ydb/bin/ydbd server --log-level 3 --syslog --tcp --yaml-config  /opt/ydb/cfg/config.yaml --grpc-port 2135 --ic-port 19001 --mon-port 8765 --node static
LimitNOFILE=65536
LimitCORE=0
LimitMEMLOCK=3221225472

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

sudo cat <<'EOF' >> /opt/ydb/cfg/config.yaml
# YDB configuration options and their values
# are described in documentaion https://ydb.tech/en/docs/deploy/configuration/config

# static erasure is the parameter that
# describes the fault tolerance mode of the
# cluster. See docs for more details https://ydb.tech/en/docs/deploy/configuration/config#domains-blob
static_erasure: mirror-3-dc
host_configs: # the list of available host configurations in the cluster.
- drive:
  - path: /dev/disk/by-partlabel/ydb_disk_ssd_01    # path of the first disk in the host configration.
    type: SSD                                       # kind of the disk: available kinds are SSD, NVME, HDD
  - path: /dev/disk/by-partlabel/ydb_disk_ssd_02
    type: SSD
  - path: /dev/disk/by-partlabel/ydb_disk_ssd_03
    type: SSD
  host_config_id: 1
hosts:
- host: ydb-node-1       # storage node DNS name
  host_config_id: 1                 # numeric host configuration template identifier
  walle_location:                   # this parameter describes where host is located.
    body: 1                         # string representing a host serial number.
    data_center: '1'           # string representing the datacenter / availability zone where the host is located.
                                    # if cluster is deployed using mirror-3-dc fault tolerance mode, all hosts must be distributed
                                    # across 3 datacenters.
    rack: '1'                       # string representing a rack identifier where the host is located.
                                    # if cluster is deployed using block-4-2 erasure, all hosts should be distrubited
                                    # accross at least 8 racks.
- host: ydb-node-2
  host_config_id: 1
  walle_location:
    body: 2
    data_center: '2'
    rack: '2'
- host: ydb-node-3
  host_config_id: 1
  walle_location:
    body: 3
    data_center: '3'
    rack: '3'
domains_config:
  # There can be only one root domain in a cluster. Domain name prefixes all scheme objects names, e.g. full name of a table table1 in database db1.
  # in a cluster with domains_config.domain.name parameter set to Root would be equal to /Root/db1/table1
  domain:
  - name: Root
    storage_pool_types:
    - kind: ssd
      pool_config:
        box_id: 1
        # fault tolerance mode name - none, block-4-2, or mirror-3-dc..
        # See docs for more details https://ydb.tech/en/docs/deploy/configuration/config#domains-blob
        erasure_species: mirror-3-dc
        kind: ssd
        geometry:
          realm_level_begin: 10
          realm_level_end: 20
          domain_level_begin: 10
          domain_level_end: 256
        pdisk_filter:
        - property:
          - type: SSD  # device type to match host_configs.drive.type
        vdisk_kind: Default
  state_storage:
  - ring:
      node: [1, 2, 3]
      nto_select: 3
    ssid: 1
table_service_config:
  sql_version: 1
actor_system_config:          # the configuration of the actor system which descibes how cores of the instance are distributed
  executor:                   # accross different types of workloads in the instance.
  - name: System              # system executor of the actor system. in this executor YDB launches system type of workloads, like system tablets
                              # and reads from storage.
    threads: 2                # the number of threads allocated to system executor.
    type: BASIC
  - name: User                # user executor of the actor system. In this executor YDB launches user workloads, like datashard activities,
                              # queries and rpc calls.
    threads: 3                # the number of threads allocated to user executor.
    type: BASIC
  - name: Batch               # user executor of the actor system. In this executor YDB launches batch operations, like scan queries, table
                              # compactions, background compactions.
    threads: 2                # the number of threads allocated to the batch executor.
    type: BASIC
  - name: IO                  # the io executor. In this executor launches sync operations and writes logs.
    threads: 1
    time_per_mailbox_micro_secs: 100
    type: IO
  - name: IC                  # the interconnect executor which YDB uses for network communications accross different nodes of the cluster.
    spin_threshold: 10
    threads: 1                # the number of threads allocated to the interconnect executor.
    time_per_mailbox_micro_secs: 100
    type: BASIC
  scheduler:
    progress_threshold: 10000
    resolution: 256
    spin_threshold: 0
blob_storage_config:         # configuration of static blobstorage group.
                             # YDB uses this group to store system tablets' data, like SchemeShard
  service_set:
    groups:
    - erasure_species: mirror-3-dc # fault tolerance mode name for the static group
      rings:          # in mirror-3-dc must have exactly 3 rings or availability zones
      - fail_domains:  # first record: fail domains of the static group describe where each vdisk of the static group should be located.
        - vdisk_locations:
          - node_id: ydb-node-1
            pdisk_category: SSD
            path: /dev/disk/by-partlabel/ydb_disk_ssd_01
        - vdisk_locations:
          - node_id: ydb-node-1
            pdisk_category: SSD
            path: /dev/disk/by-partlabel/ydb_disk_ssd_02
        - vdisk_locations:
          - node_id: ydb-node-1
            pdisk_category: SSD
            path: /dev/disk/by-partlabel/ydb_disk_ssd_03
      - fail_domains: # second ring: fail domains of the static group describe where each vdisk of the static group should be located.
        - vdisk_locations:
          - node_id: ydb-node-2
            pdisk_category: SSD
            path: /dev/disk/by-partlabel/ydb_disk_ssd_01
        - vdisk_locations:
          - node_id: ydb-node-2
            pdisk_category: SSD
            path: /dev/disk/by-partlabel/ydb_disk_ssd_02
        - vdisk_locations:
          - node_id: ydb-node-2
            pdisk_category: SSD
            path: /dev/disk/by-partlabel/ydb_disk_ssd_03
      - fail_domains: # third ring: fail domains of the static group describe where each vdisk of the static group should be located.
        - vdisk_locations:
          - node_id: ydb-node-3
            pdisk_category: SSD
            path: /dev/disk/by-partlabel/ydb_disk_ssd_01
        - vdisk_locations:
          - node_id: ydb-node-3
            pdisk_category: SSD
            path: /dev/disk/by-partlabel/ydb_disk_ssd_02
        - vdisk_locations:
          - node_id: ydb-node-3
            pdisk_category: SSD
            path: /dev/disk/by-partlabel/ydb_disk_ssd_03
channel_profile_config:
  profile:
  - channel:
    - erasure_species: mirror-3-dc
      pdisk_category: 0
      storage_pool_kind: ssd
    - erasure_species: mirror-3-dc
      pdisk_category: 0
      storage_pool_kind: ssd
    - erasure_species: mirror-3-dc
      pdisk_category: 0
      storage_pool_kind: ssd
    profile_id: 0
EOF

sudo systemctl enable --now ydbd-storage
