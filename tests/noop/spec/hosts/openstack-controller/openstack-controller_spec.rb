# ROLE: primary-controller
# ROLE: controller

require 'spec_helper'
require 'shared-examples'
manifest = 'openstack-controller/openstack-controller.pp'

describe manifest do

  before(:each) do
    Noop.puppet_function_load :is_pkg_installed
    MockFunction.new(:is_pkg_installed) do |function|
      allow(function).to receive(:call).and_return false
    end
  end

  shared_examples 'catalog' do

    let (:api_bind_address) do
      Noop.puppet_function 'get_network_role_property', 'nova/api', 'ipaddr'
    end

    workers_max          = Noop.hiera 'workers_max'
    network_metadata     = Noop.hiera_hash('network_metadata')
    use_cache            = Noop.hiera_structure 'nova/use_cache', true

    let(:memcached_servers) { Noop.hiera 'memcached_servers' }

    primary_controller = Noop.hiera 'primary_controller'
    service_endpoint = Noop.hiera 'service_endpoint'
    management_vip = Noop.hiera 'management_vip'

    let(:database_vip) { Noop.hiera('database_vip') }
    let(:nova_db_type) { Noop.hiera_structure 'nova/db_type', 'mysql+pymysql' }
    let(:nova_db_password) { Noop.hiera_structure 'nova/db_password', 'nova' }
    let(:nova_db_user) { Noop.hiera_structure 'nova/db_user', 'nova' }
    let(:nova_db_name) { Noop.hiera_structure 'nova/db_name', 'nova' }
    let(:api_db_password) do
      api_db_pass = Noop.hiera_structure 'nova/api_db_password'
      Noop.puppet_function 'pick', api_db_pass, nova_db_password
    end
    let(:api_db_user) { Noop.hiera_structure 'nova/api_db_user', 'nova_api' }
    let(:api_db_name) { Noop.hiera_structure 'nova/api_db_name', 'nova_api' }


    let(:nova_hash) { Noop.hiera_hash 'nova' }

    let(:ssl_hash) { Noop.hiera_hash 'use_ssl', {} }

    let(:internal_auth_protocol) { Noop.puppet_function 'get_ssl_property',ssl_hash,{},'keystone','internal','protocol',[nova_hash['auth_protocol'],'http'] }

    let(:internal_auth_address) { Noop.puppet_function 'get_ssl_property',ssl_hash,{},'keystone','internal','hostname',[service_endpoint, management_vip] }

    let(:admin_auth_protocol) { Noop.puppet_function 'get_ssl_property',ssl_hash,{},'keystone','admin','protocol',[nova_hash['auth_protocol'],'http'] }

    let(:admin_auth_address) { Noop.puppet_function 'get_ssl_property',ssl_hash,{},'keystone','admin','hostname',[service_endpoint, management_vip] }

    let(:keystone_auth_uri) { "#{internal_auth_protocol}://#{internal_auth_address}:5000/" }
    let(:keystone_auth_url) { "#{admin_auth_protocol}://#{admin_auth_address}:35357/" }
    let(:project_name) { Noop.puppet_function('pick', nova_hash['admin_tenant_name'], keystone_tenant) }
    let(:auth_version) { Noop.puppet_function('pick', nova_hash['auth_version'], facts[:os_service_default]) }
    let(:keystone_ec2_url) { "#{keystone_auth_uri}v2.0/ec2tokens" }

    default_log_levels_hash = Noop.hiera_hash 'default_log_levels'
    default_log_levels = Noop.puppet_function 'join_keys_to_values',default_log_levels_hash,'='

    let(:ceilometer_hash) { Noop.hiera_hash 'ceilometer', {} }
    storage_hash = Noop.hiera_structure 'storage'

    let(:auto_assign_floating_ip) { Noop.hiera 'auto_assign_floating_ip', false }
    let(:amqp_hosts) { Noop.hiera 'amqp_hosts', '' }
    let(:rabbit_hash) { Noop.hiera_hash 'rabbit', {} }
    let(:rabbit_hosts) { Noop.puppet_function 'split', amqp_hosts, ',' }
    let(:openstack_controller_hash) { Noop.hiera_hash 'openstack_controller', {} }
    let(:debug) do
      global_debug = Noop.hiera 'debug', true
      Noop.puppet_function 'pick', openstack_controller_hash['debug'], global_debug
    end
    let(:syslog_log_facility_nova) { Noop.hiera 'syslog_log_facility_nova', 'LOG_LOCAL6' }
    let(:use_syslog) { Noop.hiera 'use_syslog', true }
    let(:use_stderr) { Noop.hiera 'use_stderr', false }
    let(:nova_report_interval) { Noop.hiera 'nova_report_interval', '60' }
    let(:nova_service_down_time) { Noop.hiera 'nova_service_down_time', '180' }
    let(:notify_api_faults) { Noop.puppet_function 'pick', nova_hash['notify_api_faults'], false }
    let(:cinder_catalog_info) { Noop.puppet_function 'pick', nova_hash['cinder_catalog_info'], 'volumev2:cinderv2:internalURL' }

    let(:nova_quota) { Noop.hiera 'nova_quota', false }

    let(:glance_endpoint_default) { Noop.hiera 'glance_endpoint', management_vip }
    let(:glance_protocol) { Noop.puppet_function 'get_ssl_property',ssl_hash,{},'glance','internal','protocol','http' }
    let(:glance_endpoint) { Noop.puppet_function 'get_ssl_property',ssl_hash,{},'glance','internal','hostname', glance_endpoint_default}
    let(:glance_api_servers) { Noop.hiera 'glance_api_servers', "#{glance_protocol}://#{glance_endpoint}:9292" }

    let(:keystone_user) { Noop.puppet_function 'pick', nova_hash['user'], 'nova' }
    let(:keystone_tenant) { Noop.puppet_function 'pick', nova_hash['tenant'], 'services' }
    let(:neutron_config) { Noop.hiera_hash 'quantum_settings' }
    let(:neutron_metadata_proxy_secret) { neutron_config['metadata']['metadata_proxy_shared_secret'] }
    let(:default_floating_net) { Noop.puppet_function 'pick', neutron_config['default_floating_net'], 'net04_ext' }

    let(:fping_path) {
      if facts[:osfamily] == 'Debian'
        '/usr/bin/fping'
      else
        '/usr/sbin/fping'
      end
    }

    let(:fallback_workers) { [[facts[:processorcount].to_i, 2].max, workers_max.to_i].min }
    let(:service_workers) { nova_hash.fetch('workers', fallback_workers) }

    let(:ironic_hash) { Noop.hiera_hash 'ironic', {} }
    let(:ironic_user) { Noop.puppet_function 'pick', ironic_hash['auth_name'], 'ironic' }
    let(:ironic_password) { Noop.puppet_function 'pick', ironic_hash['user_password'], 'ironic' }
    let(:ironic_tenant) { Noop.puppet_function 'pick', ironic_hash['tenant'], 'services' }
    let(:ironic_endpoint_default) { Noop.hiera 'ironic_endpoint', management_vip }
    let(:ironic_protocol) { Noop.puppet_function 'get_ssl_property',ssl_hash,{},'ironic','internal','protocol','http' }
    let(:ironic_endpoint) { Noop.puppet_function 'get_ssl_property',ssl_hash,{},'ironic','internal','hostname', ironic_endpoint_default}

    let(:rabbit_heartbeat_timeout_threshold) { Noop.puppet_function 'pick', nova_hash['rabbit_heartbeat_timeout_threshold'], rabbit_hash['heartbeat_timeout_treshold'], 60 }
    let(:rabbit_heartbeat_rate) { Noop.puppet_function 'pick', nova_hash['rabbit_heartbeat_rate'], rabbit_hash['heartbeat_rate'], 2 }
    let(:region_name) { Noop.hiera 'region', 'RegionOne' }

    it 'should configure region name in cinder section' do
       should contain_nova_config('cinder/os_region_name').with_value(region_name)
    end

    it 'should configure RabbitMQ Heartbeat parameters' do
      should contain_nova_config('oslo_messaging_rabbit/heartbeat_timeout_threshold').with_value(rabbit_heartbeat_timeout_threshold)
      should contain_nova_config('oslo_messaging_rabbit/heartbeat_rate').with_value(rabbit_heartbeat_rate)
    end

    # TODO All this stuff should be moved to shared examples controller* tests.

    it 'should declare correct workers for systems with 4 processess on 4 CPU & 32G system' do
      should contain_class('nova::api').with(
        'osapi_compute_workers' => '4',
        'metadata_workers' => '4'
      )
      should contain_class('nova::conductor').with(
        'workers' => '4'
      )
    end

    it 'should configure workers for nova API, conductor services' do
      should contain_nova_config('DEFAULT/osapi_compute_workers').with(:value => service_workers)
      should contain_nova_config('DEFAULT/metadata_workers').with(:value => service_workers)
      should contain_nova_config('conductor/workers').with(:value => service_workers)
    end

    it 'should configure default_log_levels' do
      should contain_nova_config('DEFAULT/default_log_levels').with_value(default_log_levels.sort.join(','))
    end

    # Nova config options
    it 'nova config should have use_stderr set to false' do
      should contain_nova_config('DEFAULT/use_stderr').with(
        'value' => 'false',
      )
    end

    it 'nova config should have report_interval set to 60' do
      should contain_nova_config('DEFAULT/report_interval').with(
        'value' => '60',
      )
    end

    it 'nova config should have service_down_time set to 180' do
      should contain_nova_config('DEFAULT/service_down_time').with(
        'value' => '180',
      )
    end

    it 'nova config should contain right memcached servers list' do
      should contain_nova_config('keystone_authtoken/memcached_servers').with(
        'value' => memcached_servers.join(','),
      )
    end

    it 'should configure cinder_catalog_info for nova' do
      should contain_nova_config('cinder/catalog_info').with(:value => cinder_catalog_info)
    end

    it 'should configure nova with the basics' do
      facts[:os_workers] = 10
      max_pool_size = Noop.hiera 'max_pool_size', [facts[:os_workers] * 5 + 0, 30 + 0].min
      max_overflow = Noop.hiera 'max_overflow', [facts[:os_workers] * 5 + 0, 60 + 0].min
      idle_timeout = Noop.hiera 'idle_timeout', '3600'
      max_retries = Noop.hiera 'max_retries', '-1'

      should contain_class('nova').with(
        :rpc_backend            => 'nova.openstack.common.rpc.impl_kombu',
        :rabbit_hosts           => rabbit_hosts,
        :rabbit_userid          => rabbit_hash['user'],
        :rabbit_password        => rabbit_hash['password'],
        :image_service          => 'nova.image.glance.GlanceImageService',
        :glance_api_servers     => glance_api_servers,
        :debug                  => debug,
        :log_facility           => syslog_log_facility_nova,
        :use_syslog             => use_syslog,
        :use_stderr             => use_stderr,
        :database_idle_timeout  => idle_timeout,
        :report_interval        => nova_report_interval,
        :service_down_time      => nova_service_down_time,
        :notify_api_faults      => notify_api_faults,
        :notification_driver    => ceilometer_hash['notification_driver'],
        :cinder_catalog_info    => cinder_catalog_info,
        :database_max_pool_size => max_pool_size,
        :database_max_retries   => max_retries,
        :database_max_overflow  => max_overflow,
        :notify_on_state_change => 'vm_and_task_state',
      )
    end

    if use_cache
      it 'should configure nova::cache' do
        should contain_nova_config('cache/backend').with(
          'value' => 'oslo_cache.memcache_pool',
        )
        should contain_nova_config('cache/enabled').with(
          'value' => true,
        )
        should contain_nova_config('cache/memcache_servers').with(
          'value' => memcached_servers.join(','),
        )
      end
    end

    it 'should configure the nova database connection string' do
      if facts[:os_package_type] == 'debian'
        extra_params = '?charset=utf8&read_timeout=60'
      else
        extra_params = '?charset=utf8'
      end
      should contain_class('nova').with(
        :database_connection => "#{nova_db_type}://#{nova_db_user}:#{nova_db_password}@#{database_vip}/#{nova_db_name}#{extra_params}",
        :api_database_connection => "#{nova_db_type}://#{api_db_user}:#{api_db_password}@#{database_vip}/#{api_db_name}#{extra_params}"
      )
    end

    it 'should configure nova::keystone::authtoken' do
      should contain_class('nova::keystone::authtoken').with(
        :username          => keystone_user,
        :password          => nova_hash['user_password'],
        :project_name      => project_name,
        :auth_url          => keystone_auth_url,
        :auth_uri          => keystone_auth_uri,
        :auth_version      => auth_version,
        :memcached_servers => memcached_servers,
      )
    end

    it 'should correctly configure authtoken parameters' do
      should contain_nova_config('keystone_authtoken/username').with(:value => keystone_user)
      should contain_nova_config('keystone_authtoken/password').with(:value => nova_hash['user_password'])
      should contain_nova_config('keystone_authtoken/project_name').with(:value => project_name)
      should contain_nova_config('keystone_authtoken/auth_url').with(:value => keystone_auth_url)
      should contain_nova_config('keystone_authtoken/auth_uri').with(:value => keystone_auth_uri)
      should contain_nova_config('keystone_authtoken/auth_version').with(:value => auth_version)
      should contain_nova_config('keystone_authtoken/memcached_servers').with(:value => memcached_servers.join(','))
    end

    it 'should configure nova::api' do
      # FIXME(aschultz): check rate limits
      should contain_class('nova::api').with(
        :enabled => true,
        :api_bind_address => api_bind_address,
        :metadata_listen => api_bind_address,
        :neutron_metadata_proxy_shared_secret => neutron_metadata_proxy_secret,
        :osapi_compute_workers => service_workers,
        :metadata_workers => service_workers,
        :sync_db => primary_controller,
        :sync_db_api => primary_controller,
        :fping_path => fping_path,
        :api_paste_config => '/etc/nova/api-paste.ini',
        :default_floating_pool => default_floating_net,
        :enable_proxy_headers_parsing => true,
        :allow_resize_to_same_host => Noop.puppet_function('pick', nova_hash['allow_resize_to_same_host'], true),
      )
      if facts[:operatingsystem] == 'Ubuntu'
        should contain_tweaks__ubuntu_service_override('nova-api').with(
          :package_name => 'nova-api'
        )
      end
    end

    it 'should allow resize to same host' do
      should contain_nova_config('DEFAULT/allow_resize_to_same_host').with(
        :value => Noop.puppet_function('pick', nova_hash['allow_resize_to_same_host'], true)
      )
    end

    it 'should configure kombu compression' do
      kombu_compression = Noop.hiera 'kombu_compression', facts[:os_service_default]
      should contain_nova_config('oslo_messaging_rabbit/kombu_compression').with(:value => kombu_compression)
    end

    it 'should configure use_local for nova::conductor' do
      should contain_class('nova::conductor').with(
        :use_local => Noop.puppet_function('pick', nova_hash['use_local'], false)
      )
    end

    it 'should configure auto_assign_floating_ip if enabled' do
      if auto_assign_floating_ip
        should contain_nova_config('DEFAULT/auto_assign_floating_ip').with_value('True')
      else
        should_not contain_nova_config('DEFAULT/auto_assign_floating_ip').with_value('True')
      end
    end

    it 'should configure nova services' do
      should contain_class('nova::scheduler').with_enabled(true)
      should contain_class('nova::cert').with_enabled(true)
      should contain_class('nova::consoleauth').with_enabled(true)
    end

    it 'should configure vnc' do
      should contain_class('nova::vncproxy').with(
        :enabled => true,
        :host    => api_bind_address
      )
      if facts[:operatingsystem] == 'Ubuntu'
        if !facts.has_key?(:os_package_type) or facts[:os_package_type] == 'debian'
          nova_vncproxy_package = 'nova-consoleproxy'
        else
          nova_vncproxy_package = 'nova-vncproxy'
        end
        should contain_tweaks__ubuntu_service_override('nova-novncproxy').with(
          :package_name => nova_vncproxy_package
        )
      end
    end

    it 'should configure images settings' do
      should contain_nova_config('DEFAULT/use_cow_images').with(
        :value => Noop.hiera('use_cow_images')
      )
      should contain_nova_config('DEFAULT/force_raw_images').with(
        :value => nova_hash['force_raw_images']
      )
    end

    it 'should configure nova quota if required' do
      if nova_quota
        should contain_class('nova::quota').with('quota_driver' => 'nova.quota.DbQuotaDriver')

        {
          :quota_instances => Noop.puppet_function('pick', nova_hash['quota_instances'], 100),
          :quota_cores => Noop.puppet_function('pick', nova_hash['quota_cores'], 100),
          :quota_ram => Noop.puppet_function('pick', nova_hash['quota_ram'], 51200),
          :quota_floating_ips => Noop.puppet_function('pick', nova_hash['quota_floating_ips'], 100),
          :quota_fixed_ips => Noop.puppet_function('pick', nova_hash['quota_fixed_ips'], -1),
          :quota_metadata_items => Noop.puppet_function('pick', nova_hash['quota_metadata_items'], 1024),
          :quota_injected_files => Noop.puppet_function('pick', nova_hash['quota_injected_files'], 50),
          :quota_injected_file_content_bytes => Noop.puppet_function('pick', nova_hash['quota_injected_file_content_bytes'], 102400),
          :quota_injected_file_path_length => Noop.puppet_function('pick', nova_hash['quota_injected_file_path_length'], 4096),
          :quota_security_groups => Noop.puppet_function('pick', nova_hash['quota_security_groups'], 10),
          :quota_security_group_rules => Noop.puppet_function('pick', nova_hash['quota_security_group_rules'], 20),
          :quota_key_pairs => Noop.puppet_function('pick', nova_hash['quota_key_pairs'], 10),
          :quota_server_groups => Noop.puppet_function('pick', nova_hash['quota_server_groups'], 10),
          :quota_server_group_members => Noop.puppet_function('pick', nova_hash['quota_server_group_members'], 10),
          :reservation_expire => Noop.puppet_function('pick', nova_hash['reservation_expire'], 86400),
          :until_refresh => Noop.puppet_function('pick', nova_hash['until_refresh'], 0),
          :max_age => Noop.puppet_function('pick', nova_hash['max_age'], 0),
        }.each_pair do |config, value|
          should contain_class('nova::quota').with(config => value)
          should contain_nova_config("DEFAULT/#{config}").with(
            'value' => value,
          )
        end
      else
        should contain_class('nova::quota').with('quota_driver' => 'nova.quota.NoopQuotaDriver')
      end
    end

    ironic_enabled = Noop.hiera_structure 'ironic/enabled'
    if ironic_enabled
      it 'should declare nova::scheduler::filter class with scheduler_host_manager' do
        should contain_class('nova::scheduler::filter').with(
          'scheduler_host_manager' => 'ironic_host_manager',
        )
      end
      it 'should declare nova::ironic::common class with ironic parameters' do
        should contain_class('nova::ironic::common').with(
          'admin_username'    => ironic_user,
          'admin_password'    => ironic_password,
          'admin_tenant_name' => ironic_tenant,
          'admin_url'         => "#{keystone_auth_url}v2.0",
          'api_endpoint'      => "#{ironic_protocol}://#{ironic_endpoint}:6385/v1",
        )
      end
    end

    # TODO (iberezovskiy): In Debian open-iscsi is dependency
    # of os-brick package which is required for cinder.
    # Remove this 'if' once UCA packages are updated as well
    it 'should install open-iscsi for UCA packages if ceph is used as cinder backend' do
      if facts[:os_package_type] == 'ubuntu' and storage_hash['volumes_ceph']
        should contain_package('open-iscsi').with('ensure' => 'present')
      end
    end

    let(:compute_nodes) { Noop.puppet_function 'get_nodes_hash_by_roles', network_metadata, ['compute'] }
    let(:huge_pages_nodes) { Noop.puppet_function 'filter_nodes_with_enabled_option', compute_nodes, 'nova_hugepages_enabled' }
    let(:cpu_pinning_nodes) { Noop.puppet_function 'filter_nodes_with_enabled_option', compute_nodes, 'nova_cpu_pinning_enabled' }
    let(:enable_hugepages) { huge_pages_nodes.size() > 0 ? true : false }
    let(:enable_cpu_pinning) { cpu_pinning_nodes.size() > 0 ? true : false }

    it 'should declare nova::scheduler::filter with an appropriate filters' do
      nova_scheduler_filters         = []
      nova_scheduler_default_filters = [ 'RetryFilter', 'AvailabilityZoneFilter', 'RamFilter', 'CoreFilter', 'DiskFilter', 'ComputeFilter', 'ComputeCapabilitiesFilter', 'ImagePropertiesFilter', 'ServerGroupAntiAffinityFilter', 'ServerGroupAffinityFilter' ]
      sahara_filters                 = [ 'DifferentHostFilter' ]
      sriov_filters                  = [ 'PciPassthroughFilter','AggregateInstanceExtraSpecsFilter' ]
      huge_pages_filters             = [ 'NUMATopologyFilter' ]
      cpu_pinning_filters            = [ 'NUMATopologyFilter', 'AggregateInstanceExtraSpecsFilter' ]

      enable_sahara    = Noop.hiera_structure 'sahara/enabled', false
      enable_sriov     = Noop.hiera_structure 'quantum_settings/supported_pci_vendor_devs', false

      nova_scheduler_filters = nova_scheduler_filters.concat(nova_scheduler_default_filters)

      if enable_sahara
        nova_scheduler_filters = nova_scheduler_filters.concat(sahara_filters)
      end
      if enable_sriov
        nova_scheduler_filters = nova_scheduler_filters.concat(sriov_filters)
      end
      if enable_hugepages
        nova_scheduler_filters = nova_scheduler_filters.concat(huge_pages_filters)
      end
      if enable_cpu_pinning
        nova_scheduler_filters = nova_scheduler_filters.concat(cpu_pinning_filters)
      end

      should contain_class('nova::scheduler::filter').with(
        'scheduler_default_filters' => nova_scheduler_filters.uniq(),
      )
    end

    if primary_controller
      it 'should declare class nova::api with sync_db and sync_db_api' do
        should contain_class('nova::api').with(
          'sync_db'     => true,
          'sync_db_api' => true,
        )
      end
    end
  end # end of shared_examples

  test_ubuntu_and_centos manifest
end

