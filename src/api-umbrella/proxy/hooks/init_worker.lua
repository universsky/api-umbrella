local distributed_rate_limit_puller = require "api-umbrella.proxy.jobs.distributed_rate_limit_puller"
local distributed_rate_limit_pusher = require "api-umbrella.proxy.jobs.distributed_rate_limit_pusher"
local elasticsearch_setup = require "api-umbrella.proxy.jobs.elasticsearch_setup"
local load_api_users = require "api-umbrella.proxy.jobs.load_api_users"
local load_db_config = require "api-umbrella.proxy.jobs.load_db_config"
local resolve_backend_dns = require "api-umbrella.proxy.jobs.resolve_backend_dns"

load_db_config.spawn()
load_api_users.spawn()
resolve_backend_dns.spawn()
distributed_rate_limit_puller.spawn()
distributed_rate_limit_pusher.spawn()
elasticsearch_setup.spawn()