-- Reject authenticated submissions whose From: header is not an address the
-- logged-in account may use (the account itself and its aliases).
--
-- Postfix only checks the envelope sender (reject_sender_login_mismatch), and
-- Rspamd DKIM-signs any From: in the same domain, so without this rule
-- alice@example.com could send a correctly signed "From: ceo@example.com".
--
-- @ALLOWED@ is replaced by modules/mail.nix with a JSON object
--   { "<login>": { "addresses": [...], "regexes": [...] }, ... }
-- derived from settings.accounts.

local ucl = require "ucl"
local rspamd_regexp = require "rspamd_regexp"
local rspamd_logger = require "rspamd_logger"

local parser = ucl.parser()
assert(parser:parse_string([==[@ALLOWED@]==]))
local accounts = {}
for login, entry in pairs(parser:get_object()) do
  local addresses = {}
  for _, a in ipairs(entry.addresses) do
    addresses[a:lower()] = true
  end
  local regexes = {}
  for _, re in ipairs(entry.regexes) do
    table.insert(regexes, rspamd_regexp.create_cached(re, 'i'))
  end
  accounts[login:lower()] = { addresses = addresses, regexes = regexes }
end

local function may_use(account, address)
  if account.addresses[address] then
    return true
  end
  for _, re in ipairs(account.regexes) do
    if re:match(address) then
      return true
    end
  end
  return false
end

rspamd_config:register_symbol({
  name = 'FROM_NOT_OWNED_BY_USER',
  type = 'prefilter',
  priority = 10,
  callback = function(task)
    local user = task:get_user()
    if not user then
      return false -- not an authenticated submission
    end
    local account = accounts[user:lower()]
    local from = task:get_from('mime') or {}
    if #from == 0 then
      task:set_pre_result('reject', 'Message has no From: address', 'from_owner')
      return true
    end
    for _, f in ipairs(from) do
      local address = (f.addr or ''):lower()
      if not account or not may_use(account, address) then
        rspamd_logger.infox(task, 'user %s may not send as From: %s', user, address)
        task:set_pre_result('reject',
          string.format('You are not allowed to send as %s', address), 'from_owner')
        return true
      end
    end
    return false
  end,
})
