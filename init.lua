-- init.lua
--------------------------------------------------------
-- Notices
--------------------------------------------------------
local modname = core.get_current_modname()
local S = core.get_translator(modname)
local storage = core.get_mod_storage()
local ESC = core.formspec_escape

local NOTICE_PREFIX = "notice_"
local NEXT_ID_KEY = "notice_next_id"

jc_notices = {}
jc_notices.notices = {}

local function get_next_id()
  local id = storage:get_int(NEXT_ID_KEY)

  if id < 1 then
    id = 1
  end
  storage:set_int(NEXT_ID_KEY, id + 1)

  return id
end

local function save_notice(notice)
  storage:set_string(NOTICE_PREFIX .. notice.id, core.write_json(notice) )
end

local function load_notice(id)
  local data = storage:get_string(NOTICE_PREFIX .. id)

  if data == "" then
    return nil
  end

  local notice = core.parse_json(data)

  if type(notice) ~= "table" then
    return nil
  end

  return notice
end

local function delete_notice(id)
  storage:set_string(NOTICE_PREFIX .. id, "")
end

local function get_all_notices()
  local notices = {}
  local next_id = storage:get_int(NEXT_ID_KEY)

  if next_id < 1 then
    return notices
  end

  for id = 1, next_id - 1 do
    local notice = load_notice(id)

    if notice then
      notices[#notices + 1] = notice
    end
  end

  table.sort(notices, function(a, b)
    if a.created == b.created then
      return a.id > b.id
    end
    return a.created > b.created
  end)

  return notices
end

local function get_notice(id)
  return load_notice(tonumber(id))
end

function jc_notices.notices.get_all()
  return get_all_notices()
end

function jc_notices.notices.get(id)
  return get_notice(id)
end

function jc_notices.notices.create(title, description, player_name)
  local id = get_next_id()
  local now = os.time()
  local notice = {
    id = id,
    title = title,
    description = description,
    created = now,
    modified = now,
    created_by = player_name,
    modified_by = player_name
  }

  save_notice(notice)

  return notice
end

function jc_notices.notices.update(id, title, description, player_name)
  local notice = get_notice(id)

  if not notice then
    return false
  end

  notice.title = title
  notice.description = description
  notice.modified = os.time()
  notice.modified_by = player_name
  save_notice(notice)

  return notice
end

function jc_notices.notices.delete(id)
  if not get_notice(id) then
    return false
  end

  delete_notice(id)

  return true
end

local function has_server_priv(name)
  return core.check_player_privs(name, { server = true } )
end

local function format_date(timestamp)
  return os.date("%Y-%m-%d %H:%M", timestamp)
end

local function show_notice_formspec(name, notice, title, description)
  local formspec = {
    "formspec_version[6]",
    "size[12,8]",
    "label[0.5,0.4;" .. ESC(title or "") .. "]",
    "label[0.5,0.9;" .. ESC( S("Posted: @1", core.colorize("#FFFF00", format_date(notice.created or 0) ) ) ) .. "]",
    "label[0.5,1.2;" .. ESC( S("Posted by: @1", core.colorize("#00FF00", notice.created_by or "") ) ) .. "]",
    "textarea[0.5,1.7;11,4.5;notice_description;;" .. ESC(description or "") .. "]"
  }

  if notice.modified and notice.modified ~= notice.created then
    formspec[#formspec + 1] =
      "label[6.0,0.9;" .. ESC( S("Modified: @1", core.colorize("#FFFF00", format_date(notice.modified)) ) ) .. "]"

    formspec[#formspec + 1] =
      "label[6.0,1.2;" .. ESC( S("Modified by: @1", core.colorize("#00FF00", notice.modified_by or "") ) ) .. "]"
  end

  if has_server_priv(name) then
    formspec[#formspec + 1] =
      "button[0.5,7.0;2.5,0.8;notice_edit;" .. ESC( S("Edit") ) .. "]"

    formspec[#formspec + 1] =
      "button[3.2,7.0;2.5,0.8;notice_delete;" .. ESC( S("Delete") ) .. "]"
  end

  formspec[#formspec + 1] =
    "button[9.5,7.0;2,0.8;notice_back;" .. ESC( S("Back") ) .. "]"

  core.show_formspec(
    name,
    "jc_notices:notice:" .. notice.id,
    table.concat(formspec)
  )
end

local function show_translating_notice(name)
  local formspec = {
    "formspec_version[6]",
    "size[12,8]",
    "label[4.5,3.7;" .. ESC( S("Translating Text") ) .. "]"
  }

  core.show_formspec(
    name,
    "jc_notices:notice_translating",
    table.concat(formspec)
  )
end

local function show_translated_notice(name, notice)
  local player = core.get_player_by_name(name)

  if not player then
    return
  end

  if not jc_translate
    or not jc_translate.detect_language
    or not jc_translate.translate
    or not jc_translate.get_language
    or not jc_translate.is_enabled
  then
    show_notice_formspec(
      name,
      notice,
      notice.title or "",
      notice.description or ""
    )
    return
  end

  if not jc_translate.is_enabled(player) then
    show_notice_formspec(
      name,
      notice,
      notice.title or "",
      notice.description or ""
    )
    return
  end

  local target_language = jc_translate.get_language(player)

  if not target_language or target_language == "" then
    show_notice_formspec(
      name,
      notice,
      notice.title or "",
      notice.description or ""
    )
    return
  end

  show_translating_notice(name)

  local detection_text =
    (notice.title or "") .. "\n" .. (notice.description or "")

  jc_translate.detect_language(
    detection_text,
    function(source_language)
      if not source_language or source_language == target_language then
        show_notice_formspec(
          name,
          notice,
          notice.title or "",
          notice.description or ""
        )
        return
      end

      local title
      local description
      local title_done = false
      local description_done = false

      local function finish()
        if not title_done or not description_done then
          return
        end

        show_notice_formspec(
          name,
          notice,
          title or notice.title or "",
          description or notice.description or ""
        )
      end

      jc_translate.translate(
        notice.title or "",
        source_language,
        target_language,
        function(result)
          title = result or notice.title or ""
          title_done = true
          finish()
        end
      )

      jc_translate.translate(
        notice.description or "",
        source_language,
        target_language,
        function(result)
          description = result or notice.description or ""
          description_done = true
          finish()
        end
      )
    end
  )
end

local function show_notices(name)
  local notices = get_all_notices()
  local can_edit = has_server_priv(name)
  local row_height = 1.0
  local scroll_height = 5.8
  local scroll_max = math.max(0, math.ceil((#notices * row_height) - scroll_height))

  local formspec =
    "formspec_version[6]"
    .. "size[12,8]"
    .. "label[0.5,0.4;" .. ESC( S("Notices") ) .. "]"
    .. "box[0.4,1.0;11.2,5.9;#111111]"
    .. "scroll_container[0.6,1.2;10.8,5.5;notices_scroll;vertical;1]"

  if #notices > 0 then
    for i, notice in ipairs(notices) do
      local y = 0.2 + ((i - 1) * row_height)
      local title = notice.title or ""
      local date = format_date(notice.created or 0)

      formspec = formspec ..
        "label[0.2," .. y .. ";7.2,0.7;" .. ESC(core.colorize("#FFFF00", date ) .. " - " .. title ) .. "]" ..
        "button[7.7," .. (y - 0.08) .. ";2.6,0.6;view_notice_" .. notice.id .. ";" .. ESC( S("View Notice") ) .. "]"
    end
  else
    formspec = formspec
      .. "label[0.2,0.2;" .. ESC( S("There are no notices.") ) .. "]"
  end

  formspec = formspec
    .. "scroll_container_end[]"
    .. "scrollbaroptions[min=0;max=" .. scroll_max .. ";smallstep=1;largestep=3]"
    .. "scrollbar[11.1,1.05;0.4,5.8;vertical;notices_scroll;0]"
    .. "button_exit[9.3,7.1;2.5,0.8;notice_close;" .. ESC( S("Close") ) .. "]"

  if can_edit then
    formspec = formspec ..
      "button[0.5,7.1;2.5,0.8;notice_add;" .. ESC( S("Add Notice") ) .. "]"
  end

  core.show_formspec(name, "jc_notices:notices", formspec)
end

local function show_notice(name, id)
  local notice = get_notice(id)

  if not notice then
    core.chat_send_player(name, S("Notice not found."))
    show_notices(name)
    return false
  end

  show_translated_notice(name, notice)
  return true
end

function jc_notices.notices.show(name, id)
  return show_notice(name, id)
end

local function show_delete_confirmation(name, id)
  if not has_server_priv(name) then
    return
  end

  local notice = get_notice(id)

  if not notice then
    core.chat_send_player(name, S("Notice not found."))
    show_notices(name)
    return
  end

  local formspec = {
    "formspec_version[6]",
    "size[10,5]",
    "label[0.5,0.5;" .. ESC( S("Delete Notice") ) .. "]",
    "label[0.5,1.2;" .. ESC( S("Are you sure you want to delete this notice?") ) .. "]",
    "label[0.5,2.0;" .. ESC(notice.title or "") .. "]",
    "button[0.5,3.5;3,0.8;notice_delete_confirm;" .. ESC( S("Delete") ) .. "]",
    "button[4,3.5;3,0.8;notice_delete_cancel;" .. ESC( S("Cancel") ) .. "]"
  }

  core.show_formspec(name, "jc_notices:notice_delete:" .. id, table.concat(formspec) )
end

local function show_notice_editor(name, id)
  if not has_server_priv(name) then
    core.show_formspec(name, "jc_notices:notices", "")
    return
  end

  local notice

  if id then
    notice = get_notice(id)

    if not notice then
      core.chat_send_player(name, S("Notice not found."))
      return
    end
  end

  local title = notice and notice.title or ""
  local description = notice and notice.description or ""

  local heading = notice and S("Edit Notice") or S("Add Notice")
  local formspec = {
    "formspec_version[6]",
    "size[12,8]",
    "label[0.5,0.4;" .. ESC( heading ) .. "]",
    "field[0.5,1.4;11,0.8;notice_title;" .. ESC( S("Title") ) .. ";" .. ESC(title) .. "]",
    "textarea[0.5,2.6;11,3.8;notice_description;" .. ESC( S("Description") ) .. ";" .. ESC(description) .. "]",
    "button[0.5,6.9;3,0.8;notice_save;" .. ESC( S("Save") ) .. "]",
    "button[3.8,6.9;3,0.8;notice_cancel;" .. ESC( S("Cancel") ) .. "]"
  }

  core.show_formspec(name, "jc_notices:notice_editor:" .. (id or "new"), table.concat(formspec) )
end

core.register_chatcommand("notices", {
  description = S("View server notices."),
  func = function(name)
    show_notices(name)
    return true
  end
})

core.register_on_player_receive_fields(function(player, formname, fields)
  if not player then
    return
  end

  local name = player:get_player_name()

  if formname == "jc_notices:notices" then
    if fields.notice_close then
      core.close_formspec(name, formname)
      return
    end

    if fields.notice_add then
      if has_server_priv(name) then
        show_notice_editor(name)
      end

      return
    end

    for field, value in pairs(fields) do
      local notice_id = field:match("^view_notice_(%d+)$")

      if notice_id and value then
        jc_notices.notices.show(name, tonumber(notice_id))
        return
      end
    end

    return
  end

  local notice_id = formname:match("^jc_notices:notice:(%d+)$")

  if notice_id then
    notice_id = tonumber(notice_id)

    if fields.notice_back then
      show_notices(name)
      return
    end

    if fields.notice_edit then
      if has_server_priv(name) then
        show_notice_editor(name, notice_id)
      end

      return
    end

    if fields.notice_delete then
      if has_server_priv(name) then
        show_delete_confirmation(name, notice_id)
      end

      return
    end

    return
  end

  local delete_id = formname:match("^jc_notices:notice_delete:(%d+)$")

  if delete_id then
    delete_id = tonumber(delete_id)

    if fields.notice_delete_cancel then
      show_notice(name, delete_id)
      return
    end

    if fields.notice_delete_confirm then
      if not has_server_priv(name) then
        return
      end

      if jc_notices.notices.delete(delete_id) then
        core.chat_send_player(name, S("Notice deleted.") )
      else
        core.chat_send_player(name, S("Notice not found.") )
      end

      show_notices(name)
      return
    end

    return
  end

  local editor_id = formname:match( "^jc_notices:notice_editor:(.+)$" )

  if editor_id then
    if not has_server_priv(name) then
      return
    end

    if fields.notice_cancel then
      show_notices(name)
      return
    end

    if fields.notice_save then
      local title = fields.notice_title or ""
      local description = fields.notice_description or ""

      if title == "" then
        core.chat_send_player(name, S("A notice title is required.") )
        return
      end

      if description == "" then
        core.chat_send_player(name, S("A notice description is required.") )
        return
      end

      if editor_id == "new" then
        jc_notices.notices.create(title, description, name )

        core.chat_send_player(name, S("Notice added.") )
      else
        local id = tonumber(editor_id)

        if jc_notices.notices.update(id, title, description, name) then
          core.chat_send_player(name, S("Notice updated.") )
        else
          core.chat_send_player(name, S("Notice not found.") )
        end
      end

      show_notices(name)
      return
    end
  end
end)