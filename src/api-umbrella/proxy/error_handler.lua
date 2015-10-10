local is_array = require "api-umbrella.utils.is_array"
local lustache = require "lustache"
local mustache_unescape = require "api-umbrella.utils.mustache_unescape"
local path = require "pl.path"
local stringx = require "pl.stringx"
local tablex = require "pl.tablex"
local utils = require "api-umbrella.proxy.utils"

local deep_merge_overwrite_arrays = utils.deep_merge_overwrite_arrays
local deepcopy = tablex.deepcopy
local extension = path.extension
local strip = stringx.strip

local supported_media_types = {
  {
    format = "json",
    media_type = "application",
    media_subtype = "json",
  },
  {
    format = "xml",
    media_type = "application",
    media_subtype = "xml",
  },
  {
    format = "xml",
    media_type = "text",
    media_subtype = "xml",
  },
  {
    format = "csv",
    media_type = "text",
    media_subtype = "csv",
  },
  {
    format = "html",
    media_type = "text",
    media_subtype = "html",
  },
}

local supported_formats = {}
for _, media in ipairs(supported_media_types) do
  if not supported_formats[media["format"]] then
    supported_formats[media["format"]] = media["media_type"] .. "/" .. media["media_subtype"]
  end
end

local function request_format()
  local request_path = ngx.ctx.uri
  if request_path then
    local format = extension(request_path)
    if format then
      format = string.sub(format, 2)
      if supported_formats[format] then
        return format, supported_formats[format]
      end
    end
  end

  local format_arg = ngx.var.arg_format
  if format_arg then
    if supported_formats[format_arg] then
      return format_arg, supported_formats[format_arg]
    end
  end

  local accept_header = ngx.var.http_accept
  if accept_header then
    local media = utils.parse_accept(accept_header, supported_media_types)
    if media then
      return media["format"], media["media_type"] .. "/" .. media["media_subtype"]
    end
  end

  return "json", supported_formats["json"]
end

local function render_template(template, data, format, strip_whitespace)
  if not template or type(template) ~= "string" then
    ngx.log(ngx.ERR, "render_template passed invalid template (not a string)")
    return nil, "template error"
  end

  if not data or type(data) ~= "table" or is_array(data) then
    ngx.log(ngx.ERR, "render_template passed invalid data (not a table)")
    return nil, "template error"
  end

  -- Disable Mustache HTML escaping by default for non XML or HTML responses.
  if format ~= "xml" and format ~= "html" then
    template = mustache_unescape(template)
  end

  if strip_whitespace then
    -- Strip leading and trailing whitespace from template, since it's easy to
    -- introduce in multi-line templates and XML doesn't like if there's any
    -- leading space before the XML declaration.
    template = strip(template)
  end

  if format == "json" then
    for key, value in pairs(data) do
      data[key] = ndk.set_var.set_quote_json_str(value)
    end
  elseif format == "csv" then
    for key, value in pairs(data) do
      -- Quote the values for CSV output
      data[key] = '"' .. string.gsub(value, '"', '""') .. '"'
    end
  end

  local ok, output = pcall(lustache.render, lustache, template, data)
  if ok then
    return output
  else
    ngx.log(ngx.ERR, "Mustache rendering error while rendering error template. Error: ", output, " Template: ", template)
    return nil, "template error"
  end
end

return function(denied_code, settings, extra_data)
  -- Store the gatekeeper rejection code for logging.
  ngx.ctx.gatekeeper_denied_code = denied_code

  if not settings then
    settings = config["apiSettings"]
  end

  local format, content_type = request_format()

  local data = deepcopy(settings["error_data"][denied_code])
  if not data or type(data) ~= "table" or is_array(data) then
    data = deepcopy(settings["error_data"]["internal_server_error"])
  end

  local message_data = deep_merge_overwrite_arrays({
    ["baseUrl"] = utils.base_url(),
  }, extra_data)
  data["message"] = render_template(data["message"], message_data)

  local status_code = data["status_code"]
  if not status_code then
    status_code = 500
  end

  local template = settings["error_templates"][format]
  local output, template_err = render_template(template, data, format, true)

  -- Allow all errors to be loaded over CORS (in case any underlying APIs are
  -- expected to be accessed over CORS then we want to make sure errors are
  -- also allowed via CORS).
  ngx.header["Access-Control-Allow-Origin"] = "*"

  if not template_err then
    ngx.status = status_code
    ngx.header.content_type = content_type
    ngx.print(output)
    return ngx.exit(ngx.HTTP_OK)
  else
    ngx.status = 500
    ngx.header.content_type = "text/plain"
    ngx.print("Internal Server Error")
    return ngx.exit(ngx.HTTP_OK)
  end
end