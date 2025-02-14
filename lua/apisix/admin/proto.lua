local type = type
local ipairs = ipairs
local core = require("apisix.core")
local get_routes = require("apisix.http.router").http_routes
local get_services = require("apisix.http.service").services
local tostring = tostring


local _M = {
    version = 0.1,
}


local function check_conf(id, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing proto id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong proto id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong proto id"}
    end

    core.log.info("schema: ", core.json.delay_encode(core.schema.proto))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.proto, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    return need_id and id or true
end


function _M.put(id, conf)
    local id, err = check_conf(id, conf, true)
    if not id then
        return 400, err
    end

    local key = "/proto/" .. id
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put proto[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(id)
    local key = "/proto"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key)
    if not res then
        core.log.error("failed to get proto[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.post(id, conf)
    local id, err = check_conf(id, conf, false)
    if not id then
        return 400, err
    end

    local key = "/proto"
    -- core.log.info("key: ", key)
    local res, err = core.etcd.push("/proto", conf)
    if not res then
        core.log.error("failed to post proto[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end

function _M.check_proto_used(plugins, deleting, ptype, pid)

    core.log.info("plugins1: ", core.json.delay_encode(plugins, true))

    if plugins then
        if type(plugins) == "table" and plugins["grpc-proxy"]
           and plugins["grpc-proxy"].proto_id
           and tostring(plugins["grpc-proxy"].proto_id) == deleting then
            return 400, {error_msg = "can not delete this proto,"
                                     .. ptype .. " [" .. pid
                                     .. "] is still using it now"}
        end
    end
end

function _M.delete(id)
    if not id then
        return 400, {error_msg = "missing proto id"}
    end

    local routes, routes_ver = get_routes()

    core.log.info("routes: ", core.json.delay_encode(routes, true))
    core.log.info("routes_ver: ", routes_ver)

    if routes_ver and routes then
        for _, route in ipairs(routes) do
            if type(route) == "table" and route.value
               and route.value.plugins then
                  return _M.check_proto_used(route.value.plugins, id, "route", route.value.id)
            end
        end
    end

    local services, services_ver = get_services()

    core.log.info("services: ", core.json.delay_encode(services, true))
    core.log.info("services_ver: ", services_ver)

    if services_ver and services then
        for _, service in ipairs(services) do
            if type(service) == "table" and service.value
               and service.value.plugins then
                  return _M.check_proto_used(service.value.plugins, id, "service", service.value.id)
            end
        end
    end

    local key = "/proto/" .. id
    -- core.log.info("key: ", key)
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete proto[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
