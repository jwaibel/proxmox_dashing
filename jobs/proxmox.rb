require 'json'
require 'rest_client'
require 'socket'
require 'timeout'

def get_node_kernel(node)
  @site["nodes/#{node}/status"].get @auth_params do |response, request, result, &block|
    JSON.parse(response.body)['data']['kversion'].split[1]
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


def is_listening?(hostname)
  uri       = "https://#{hostname}:8006/api2/json/"
  p RestClient::Resource.new(uri, :verify_ssl => false, open_timeout: 3)
end

def is_port_open?(ip, port)
  begin
    Timeout::timeout(1) do
      begin
        s = TCPSocket.new(ip, port)
        s.close
        return true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        return false
      end
    end
  rescue Timeout::Error
  end
  false
end

def get_config
  config = {}
  config['proxmox_hosts'] = ["kvm0v3.jnb1.host-h.net", "kvm1v3.jnb1.host-h.net", "kvm2v3.jnb1.host-h.net", "kvm3v3.jnb1.host-h.net", "kvm4v3.jnb1.host-h.net","kvm5v3.jnb1.host-h.net","kvm0v3.cpt3.host-h.net"]
  config['bad_nodes']  = {}
  config['good_nodes'] = []
  config['username']   = 'proxmoxdasher'
  config['password']   = 'eevai8Jo'
  config['realm']      = 'pve'
  config['port']       = 8006
  return config
end

def classify_nodes(config)
  config['proxmox_hosts'].each do |host|
    if is_port_open?(host,config['port'])
      uri       = "https://#{host}:#{config['port']}/api2/json/"
      post_param = { username: config['username'], realm: config['realm'], password: config['password'] }
      begin
        site = RestClient::Resource.new(uri, :verify_ssl => false, open_timeout: 3)
        response = site['access/ticket'].post post_param do |response, request, result, &block|
          if response.code == 200
            config['bad_nodes'].delete(host) if config['bad_nodes'].include?(host)
            config['good_nodes'] << host unless config['good_nodes'].include?(host)
          else
            config['good_nodes'].delete(host) if config['good_nodes'].include?(host)
            config['bad_nodes'][host] = "cannot authenticate"
          end
        end
      rescue Exception
        config['good_nodes'].delete(host) if config['good_nodes'].include?(host)
        config['bad_nodes'][host] = "cannot authenticate"
      end
    else
      config['good_nodes'].delete(host) if config['good_nodes'].include?(host)
        config['bad_nodes'][host] = "not listening"
    end
    config
  end
end

def report_cluster_status
	nodes = []
  nodes = @status.select { |a| a['type'] == 'node'}

  norgmanagerlist = select_hosts(nodes,'rgmanager',0)
  downhostlist = select_hosts(nodes, 'state',0)
  nopmxcfshostlist = select_hosts(nodes, 'pmxcfs',0)
  

  ha_hosts_array = @status.select { |a| a['type'] == 'group'}
  down_ha_hosts = ha_hosts_array.select { |a| a['state'] != '112' }
  down_ha_host_ids = down_ha_hosts.map { |x| x["name"] }



  send_event('pvecluster', { status: 'CRITICAL', message: "Too many nodes not running pvecluster: #{nopmxcfshostlist.join(", ")}", status:'Critical' } ) if nopmxcfshostlist.size >= 2
  if nopmxcfshostlist.empty?
    send_event('pvecluster', { status: 'OK', message: 'Cluster has quorum', status:'OK' } )
  else
    send_event('pvecluster', { status: 'Warning', message: "PVECluster not running on:\n #{nopmxcfshostlist.join(", ")}"} )
  end
  

  send_event('corosync', { status: 'CRITICAL', message: 'Cluster lost quorum', status:'Critical' } ) unless have_quorum(@status)
  if downhostlist.empty?
    send_event('corosync', { status: 'OK', message: "Corosync up on all hosts"} )
  else
    send_event('corosync', { status: 'Warning', message: "Node(s) not running: \n #{downhostlist.join(", ")}" } )
  end
  unless norgmanagerlist.empty?
    send_event('rgmanager', { status: 'CRITICAL', message: "Node(s) not running RG Manager: \n #{norgmanagerlist.join(", ")}" } )
  else
    send_event('rgmanager', { status: 'OK', message: 'RGmanager is healthy' } )
  end

  unless down_ha_host_ids.empty?
    send_event('haservers', { status: 'CRITICAL', message: "HA servers down: \n #{down_ha_host_ids.join(", ")}" } )
  else
    send_event('haservers', { status: 'OK', message: 'All HA servers are running' } )
  end
end

def report_total_failure
    p "Setting all blocks to critical, beacuse no hosts are reachable"
    send_event('pvecluster', { status: 'CRITICAL', message: "KVM cluster unreachable" } )
    send_event('corosync', { status: 'CRITICAL', message: "KVM cluster unreachable"} )
    send_event('rgmanager', { status: 'CRITICAL', message: "KVM cluster unreachable" } )
    send_event('haservers', { status: 'CRITICAL', message: "KVM cluster unreachable" })
end

def bad_nodes_report(conf)
  rows = []
  unless conf['bad_nodes'].empty?
    conf['bad_nodes'].each do |name, reason|
      rows << {"cols"=> [{"value" => name} ,{"value" => reason }] }
    end
  end
  rows
end
def check_response(response)
  if response.code == 200
    JSON.parse(response.body)['data']
  else
    'NOK: error code = ' + response.code.to_s
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
  begin
    @site['access/ticket'].post post_param do |response, request, result, &block|
      if response.code == 200
        extract_ticket response
      else
        @connection_status = 'error'
      end
    end
  rescue Exception
    p @connection_status
  end
end



@conf=get_config()
SCHEDULER.every '2s' do
@auth_params = create_ticket

  classify_nodes(conf)
  report_total_failure if conf['good_nodes'].empty?
  hostname = conf['good_nodes'].shuffle.first
  uri = "https://#{hostname}:#{conf['port']}/api2/json/"
  @site = RestClient::Resource.new(uri, :verify_ssl => false)
  @site["cluster/status"].get @auth_params do |response, request, result, &block|
    @status = check_response(response)
    p @status
  end
end


  
  #populate data from random good node

#  conf['good_nodes'].each do |node|
#    rows << {"cols"=> [{"value" => node['name']} ,{"value" => get_node_kernel(node['name'])}] }
#  end


#   status = get_data()
#   p status
#    report_cluster_status

#  else
#    send_event('hosts_and_kernels', { rows: rows } )
#  conf['good_nodes'].each do |node|
#    rows << {"cols"=> [{"value" => node['name']} ,{"value" => get_node_kernel(node['name'])}] }
#  end
#  conf['bad_nodes'].each do |k, v|
#    rows << {"cols"=> [{"value" => k} ,{"value" => v }] }
#  end
#send_event('hosts_and_kernels', { rows: rows } )




#  p @status
#  if @status.class == Array
#  p @status
#  else
#    @status = get_data
#  p @status
#  end
