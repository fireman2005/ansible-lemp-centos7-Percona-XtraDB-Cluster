# ansible-lemp-centos7-Percona-XtraDB-Cluster
Full webstack - Centos 7, LEMP, Nginx, Percona-XtraDB-Cluster, PHP-FPM 5

- Requirements
	- Vagrant with Virtual Box
	- Ansible

- Get Centos 7 Box
	- You can create clean centos 7 base box.
	This is my guide: 
	http://linoxide.com/linux-how-to/setup-centos-7-vagrant-base-box-virtualbox/
	
	- You can download clear centos 7 base box:
	https://atlas.hashicorp.com/bento/boxes/centos-7.1

	- Default installed account:
		- vagrant/vagrant

- Check out this git. Type this command:
	
		git clone git@github.com:fireman2005/ansible-lemp-centos7-percona-xtradb-cluster.git

- Local vagrant developement machine
	- Move to check out folder
	- vagrant box add db-cluster your_centos_7_box_location
	- vagrant up
	- vagrant provision (to run ansible if vagrant up is not run provision automatically)
	- vagrant ssh (access to your new virtual machine)

- Production server
	- Move to check_out_folder/ansible
	- Create your_server_role_config.yml. Here is an example:
		  - hosts: host_config_name
		  sudo: yes
		  roles:
		  - common
		  - percona
		  - nginx
		  - php-fpm-55
		  - nginx-conf

	- Add server ip address in to hosts. Here is an example:
	
		[host_config_name]
		192.168.100.xxx

	- Type this command to run ansible (ansible must be installed)
		ansible-playbook -i ./hosts -u your_server_ssh_account your_server_role_config.yml

- Any questions? Please add new issue or send me email <fireman_2005@mail.ru>
