require 'rest_client'
require 'json'

set :kvm_rows, []

def get_data(proxmox_hosts)
  connect_to_node(proxmox_hosts)
  begin
    @site["cluster/status"].get @auth_params do |response, request, result, &block|
      JSON.parse(response.body)['data']
    end
  rescue => e
    connect_to_node(proxmox_hosts)
  end
end

def extract_ticket(response)
  data = JSON.parse(response.body)
  ticket = data['data']['ticket']
  csrf_prevention_token = data['data']['CSRFPreventionToken']
  unless ticket.nil?
    token = 'PVEAuthCookie=' + ticket.gsub!(/:/, '%3A').gsub!(/=/, '%3D')
  end
  @connection_status = 'connected'
  {
    CSRFPreventionToken: csrf_prevention_token,
    cookie: token
  }
end

def create_ticket
  post_param = { username: @username, realm: @realm, password: @password }
  @site['access/ticket'].post post_param do |response, request, result, &block|
    if response.code == 200
      extract_ticket response
    else
      @connection_status = 'error'
    end
  end
end

def get_node_status(node)
	@site["nodes/#{node}/status"].get @auth_params do |response, request, result, &block|
		return check_response(response)
	end
end

def have_quorum(status)
  quorum_line = status.find { |a| a['type'] == 'quorum'}
  quorate = quorum_line['quorate'].to_i
  if quorate == 0
    false
  else
    true
  end
end

def select_hosts(nodes, attribute, value=0)
    nodes_array = nodes.select { |a| a[attribute] == value }
    nodes_array.map { |x| x["name"] }
end

def connect_to_node(proxmox_hosts)
  @host      = proxmox_hosts.shuffle.first
  p "Connecting to: #{@host}"
  uri       = "https://#{@host}:8006/api2/json/"
  @username = 'proxmoxdasher'
  @password = 'eevai8Jo'
  @realm    = 'pve'
  @connection_status = ''
  @status   = {}
  @site = RestClient::Resource.new(uri, :verify_ssl => false)
  @auth_params = create_ticket
end

def get_cluster_status
	nodes = []
  nodes = @status.select { |a| a['type'] == 'node'}
  norgmanagerlist = select_hosts(nodes,'rgmanager',0)
  downhostlist = select_hosts(nodes, 'state',0)
  nopmxcfshostlist = select_hosts(nodes, 'pmxcfs',0)

  send_event('pvecluster', { status: 'CRITICAL', message: 'Cluster lost quorum', status:'Critical' } ) unless have_quorum(@status)
  if have_quorum(@status) and nopmxcfshostlist.empty?
    send_event('pvecluster', { status: 'OK', message: 'Cluster has quorum', status:'OK' } )
  else
    send_event('pvecluster', { status: 'Warning', message: "Corosync not running on:\n #{nopmxcfshostlist.join}\n"} )
  end
  
#  unless downhostlist.empty?
#    send_event('corosync', { status: 'Warning', message: "Node(s) not running: \n #{downhostlist}" } )
#  else
#    send_event('corosync', { status: 'OK', message: "All hosts are up" } )
#  end
#
#  unless norgmanagerlist.empty?
#    send_event('rgmanager', { status: 'CRITICAL', message: "Node(s) not running RG Manager: \n #{norgmanagerlist}" } )
#  else
#    send_event('rgmanager', { status: 'OK', message: 'RGmanager is healthy' } )
#  end

#  @ha_hosts = nodes.select { |a| a['type'] == 'group'}
#	nodes.each do | node |
#    p node.inspect
#			@status = "OFFLINE"
#  end
end

proxmox_hosts = ["kvm0v3.jnb1.host-h.net", "kvm1v3.jnb1.host-h.net", "kvm2v3.jnb1.host-h.net", "kvm3v3.jnb1.host-h.net", "kvm4v3.jnb1.host-h.net"]

SCHEDULER.every '2s' do
  @status = get_data(proxmox_hosts)
  if @status.class == Array
    get_cluster_status
  else
    p "Host #{@host} not participating in cluster, connecting to new host"
    @status = get_data(proxmox_hosts)
  end
end
