# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
	3.times do |n|
		config.vm.define "pm"+(1+n).to_s do |cc|
					cc.vm.host_name = "pm" + (1+n).to_s
					cc.vm.network :private_network, ip: "10.10.10.1" + n.to_s
					if	cc.vm.hostname == "pm1" then
							cc.vm.network "forwarded_port", guest: 3306, host: 3307
							cc.vm.box = "centos/8"
							cc.vm.box_check_update = true
							cc.vm.provider :virtualbox do |vb|
								vb.gui = false
								vb.memory = "1024"
								vb.cpus = 2
								vb.name = "pm"+(1+n).to_s
							end
					end
					if	cc.vm.hostname == "pm2" then
							cc.vm.network "forwarded_port", guest: 3306, host: 3308
							cc.vm.box = "centos/8"
							cc.vm.box_check_update = true
							cc.vm.provider :virtualbox do |vb|
								vb.gui = false
								vb.memory = "1024"
								vb.cpus = 2
								vb.name = "pm"+(1+n).to_s
							end
					end
					if	cc.vm.hostname == "pm3" then
							cc.vm.network "forwarded_port", guest: 3306, host: 3309
							cc.vm.box = "centos/8"
							cc.vm.box_check_update = true
							cc.vm.provider :virtualbox do |vb|
								vb.gui = false
								vb.memory = "1024"
								vb.cpus = 2
								vb.name = "pm"+(1+n).to_s
							end
					end
		end
	end
	1.times do |n|
		config.vm.define "mx"+(1+n).to_s do |cc|
					cc.vm.host_name = "mx" + (1+n).to_s
					cc.vm.network :private_network, ip: "10.10.10.2" + n.to_s
					if	cc.vm.hostname == "mx1" then
							cc.vm.network "forwarded_port", guest: 3306, host: 3310
							cc.vm.network "forwarded_port", guest: 8989, host: 8989
							cc.vm.box = "centos/8"
							cc.vm.box_check_update = true
							cc.vm.provider :virtualbox do |vb|
								vb.gui = false
								vb.memory = "1024"
								vb.cpus = 2
								vb.name = "mx"+(1+n).to_s
							end
					end
		end
	end
end
