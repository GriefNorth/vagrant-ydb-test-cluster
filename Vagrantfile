ENV['VAGRANT_DEFAULT_PROVIDER'] = 'libvirt'

Vagrant.configure("2") do |config|
  
  config.ssh.insert_key = false
  config.vm.provider :libvirt do |v|
    v.memory = 8192
    v.cpus = 2
    v.storage_pool_name = "default"
    v.driver = "kvm"
    v.video_type = "vga"
    v.graphics_type = "spice"
    v.storage_pool_name = "VMs"
    v.storage :file, :size => '80G', :bus => 'scsi', :type => 'raw', :discard => 'unmap', :detect_zeroes => 'on'
    v.storage :file, :size => '80G', :bus => 'scsi', :type => 'raw', :discard => 'unmap', :detect_zeroes => 'on'
    v.storage :file, :size => '80G', :bus => 'scsi', :type => 'raw', :discard => 'unmap', :detect_zeroes => 'on'
  end

  ##### DEFINE VM #####
  (1..3).each do |i|
    config.vm.define "ydb-node-#{i}" do |config|
    config.vm.hostname = "ydb-node-#{i}"
    config.vm.box = "debian/bullseye64"
    config.vm.box_check_update = false
    config.vm.network :public_network, 
        :ip => "192.168.124.1#{i}0",
        :dev => "virbr0",
        :mode => "bridge",
        :type => "bridge"
    config.vm.provision "shell", path: "provision.sh"
    end
    config.vm.synced_folder ".", "/vagrant", disabled: true
  end
end