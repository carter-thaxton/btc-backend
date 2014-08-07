hackOregonBackEnd
=================

The back end consists of a postgres database and an OpenResty/Nginx server. This is put together in such a way that all endpoints can be built entirely inside of postgres functions. See the file install.sql for several examples of these endpoint functions, including get_top_committee_data(). 

This repo contains all scripts needed to build hack oregon's back end in a vagrant virtual machine.

To install the backend:

1) Virtual box and vagrant must be installed.

		See https://www.virtualbox.org/ for virtual box.
	
		See http://www.vagrantup.com/ for vagrant.

	
2) Copy this git repository to a folder on your computer, make that folder your working directory
These files should be in the folder:

	install2.sh : installation of openresty and other configurations
	install3.sh : installation of the Hack Oregon database
	appendToBash.bashrc
	install.sql : Connection of restful requests to postgres functions / postgres side
	nginx.conf : Connection of restful requests to postgres functions / nginx side
	Vagrantfile.final : Adds mapping of vagrant port 80 to host port 8080 so that web pages are available outside the vagrant machine
	
3) Run these commands (note: you may have to run chmod 777 installx.sh on each of the installx.sh scripts so that they can be executed. Also, you may have to enter Y partway through the installation of postgres; haven't found what option I need to use to skip that):


	host machine prompt> vagrant box add ubuntu14 https://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-i386-vagrant-disk1.box
	host machine prompt> vagrant init ubuntu14
	host machine prompt> vagrant up
	host machine prompt> vagrant ssh
	guest machine prompt> sudo /vagrant/install2.sh
	guest machine prompt> sudo /vagrant/install3.sh

4) enter ctrl + d then run these commands:

	host machine prompt> vagrant reload
	host machine prompt> vagrant ssh
	guest machine prompt> sudo /usr/local/openresty/nginx/sbin/nginx
5) Enter ctrl + d to exit ssh

Go to:
	http://localhost:8080/ 
on the host machine’s browser, the nginx welcome page should be seen.
Go to:

	http://localhost:8080/hackoregon/http/top_committee_data/4/
	
on the host machine’s browser,  JSON output should be seen. 


