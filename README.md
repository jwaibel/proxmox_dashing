This repo should help you get started with proxmox cluster health monitoring with dashing.
It connects to all 'good' nodes in the cluster and does a cluster status check
to visually display the state of:
* PVE Cluster health
* Corosync quorum
* RGManager state
* HA Servers state

Each of the above widgets use the Hot Status widget https://gist.github.com/yannrouillard/796fe74d4cbf0cf42f47
to display the health of the monitored item.
The alert thresholds are currently hardcoded (eg. 1 host down warning and > 2 critical).
The dashboard will also play an alert sound when a critical state is triggered.
It also includes a widget displaying a list of the KVM hosts in the cluster
with their running kernel versions.

Requirements:
* rvm, bundler
* Javascript runtime package (like nodejs)

Installation and configuration:
* clone the repo
* do a bundle install
* create a config file (see sample config in shared) in the shared directory
* cd proxmox_dashing
* dashing start

This has been tested and works with Apache Passenger and Unicorn as webservices.
Please see the official dashing documentation about configuration of webservices.
For this and information about dashing check out the official documentation: http://shopify.github.com/dashing

In addition to the dashing frontend, it also makes use of the dashing contrib extention libraries to offer api
access to state information of each widget, wich is awesome if you want to build some physical alert system around it.
https://github.com/QubitProducts/dashing-contrib

Some screenshots:
Cluster health good: http://snag.gy/pMeHl.jpg
