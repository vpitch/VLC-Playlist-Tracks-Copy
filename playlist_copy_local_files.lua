-- <Extension Name>
-- Copyright (c) 2026 pitch the switch
--
-- This software is released under the MIT License.
-- See the LICENSE file in the project root for full license information.

-- playlist_copy_local_files.lua
-- VLC Lua extension: copy local media files from current playlist to a destination folder.
--
-- macOS install path (user):
--   ~/Library/Application Support/org.videolan.vlc/lua/extensions/
-- Then restart VLC and open:
--   View -> Extensions -> Playlist Local File Copier

local dlg = nil
local input_dest = nil
local label_status = nil
local list_log = nil

local log_file = nil
local log_counter = 0
local running = false

-- Keep dialog compact on small screens; controls still scale inside this grid.
local GRID_COLS = 3

function descriptor()
    return {
        title = "Playlist Local File Copier",
        version = "1.1.2",
        author = "Codex",
        shortdesc = "Copy local playlist files",
        description = "Copies local files (file://) from current playlist to a chosen folder.",
        capabilities = {}
    }
end

function activate()
    build_ui()
end

function deactivate()
    close_log()
    if dlg then
        dlg:delete()
        dlg = nil
    end
end

function close()
    vlc.deactivate()
end

local function trim(s)
    if not s then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function shell_quote(s)
    s = tostring(s or "")
    return "'" .. s:gsub("'", "'\"'\"'") .. "'"
end

local function cmd_success(cmd)
    local r1, _, r3 = os.execute(cmd)
    if type(r1) == "number" then
        return r1 == 0
    end
    if type(r1) == "boolean" then
        if r1 then
            if r3 ~= nil then return r3 == 0 end
            return true
        end
        return false
    end
    return false
end

local function join_path(a, b)
    if not a or a == "" then return b end
    if a:sub(-1) == "/" then return a .. b end
    return a .. "/" .. b
end

local function basename(path)
    if not path then return "" end
    local name = path:match("([^/]+)$")
    return name or path
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

local function ensure_writable_dir(path)
    if path == "" then
        return false, "Destination path is empty"
    end

    local mk = "/bin/mkdir -p " .. shell_quote(path) .. " >/dev/null 2>&1"
    if not cmd_success(mk) then
        return false, "Cannot create destination folder: " .. path
    end

    local testfile = join_path(path, ".vlc_write_test_" .. tostring(os.time()))
    local f, err = io.open(testfile, "wb")
    if not f then
        return false, "No write permission for destination: " .. tostring(err)
    end
    f:write("ok")
    f:close()
    os.remove(testfile)

    return true
end

local function expand_home(path)
    path = trim(path)
    if path:sub(1, 2) == "~/" then
        local home = os.getenv("HOME") or ""
        return home .. path:sub(2)
    elseif path == "~" then
        return os.getenv("HOME") or "~"
    end
    return path
end

local function url_decode(s)
    if not s then return nil end
    s = s:gsub("+", " ")
    s = s:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return s
end

local function file_uri_to_path(uri)
    if not uri or uri == "" then return nil end

    if uri:match("^file://") then
        local p = uri
        p = p:gsub("^file://localhost", "")
        p = p:gsub("^file://", "")
        p = url_decode(p)
        if p and p ~= "" then return p end
        return nil
    end

    if uri:sub(1, 1) == "/" then
        return uri
    end

    return nil
end

local function is_local_media_uri(uri)
    if not uri then return false end
    if uri:match("^file://") then return true end
    if uri:sub(1, 1) == "/" then return true end
    return false
end

local function set_status(s)
    if label_status then label_status:set_text(s or "") end
end

local function close_log()
    if log_file then log_file:close() log_file = nil end
end

local function append_ui_log(msg)
    msg = tostring(msg or "")
    log_counter = log_counter + 1
    if list_log then
        list_log:add_value(msg, log_counter)
    end
end

local function append_file_log(msg)
    msg = tostring(msg or "")

    if log_file then
        log_file:write(msg .. "\n")
        log_file:flush()
    end
end

local function clear_log_ui()
    log_counter = 0
    if list_log then list_log:clear() end
end

function flatten_playlist(node, out)
    if type(node) ~= "table" then return end

    local has_media_ref = (node.path ~= nil) or (node.uri ~= nil)
    if has_media_ref then
        out[#out + 1] = node
    end

    if type(node.children) == "table" then
        for _, child in ipairs(node.children) do
            flatten_playlist(child, out)
        end
    end
end

local function get_playlist_tree()
    local candidates = {
        {name = "playlist", include_meta = false},
        {name = "normal", include_meta = false},
        {name = "playlist", include_meta = true},
        {name = "normal", include_meta = true}
    }

    for _, c in ipairs(candidates) do
        local ok, result = pcall(function()
            return vlc.playlist.get(c.name, c.include_meta)
        end)
        if ok and type(result) == "table" then
            return result
        end
    end

    return {}
end

local function collect_playlist_items_flat()
    local tree = get_playlist_tree()
    local out = {}

    if tree.children or tree.path or tree.uri then
        flatten_playlist(tree, out)
    else
        for _, n in ipairs(tree) do
            flatten_playlist(n, out)
        end
    end

    return out
end

local function copy_file_lua(src, dst)
    local in_f, in_err = io.open(src, "rb")
    if not in_f then
        return false, "Cannot open source: " .. tostring(in_err)
    end

    local out_f, out_err = io.open(dst, "wb")
    if not out_f then
        in_f:close()
        return false, "Cannot create destination file: " .. tostring(out_err)
    end

    while true do
        local chunk = in_f:read(1024 * 1024)
        if not chunk then break end
        local ok, werr = out_f:write(chunk)
        if not ok then
            in_f:close()
            out_f:close()
            os.remove(dst)
            return false, "Write error: " .. tostring(werr)
        end
    end

    in_f:close()
    out_f:close()
    return true
end

local function copy_file_safe(src, dst)
    local ok, err = copy_file_lua(src, dst)
    if ok then return true end

    local cmd = "/bin/cp -n " .. shell_quote(src) .. " " .. shell_quote(dst) .. " >/dev/null 2>&1"
    if cmd_success(cmd) then return true end

    return false, (err or "Unknown copy error") .. " ; fallback cp failed"
end

local function pick_folder_finder()
    -- Returns: path, err_kind ("cancelled" | "failed"), err_msg
    -- Keep it as a single AppleScript expression: this avoids parser issues
    -- seen in some VLC/macOS environments with multi-line try/on error.
    local cmd = "/usr/bin/osascript"
        .. " -e "
        .. shell_quote("POSIX path of (choose folder with prompt \"Select destination folder\")")
        .. " 2>&1"

    local p = io.popen(cmd, "r")
    if not p then
        return nil, "failed", "cannot run osascript"
    end

    local out = p:read("*a") or ""
    p:close()
    out = trim(out)

    if out == "" then
        return nil, "cancelled", "dialog cancelled"
    end

    if out:match("^osascript:") then
        local low = out:lower()
        if low:find("user canceled", 1, true) or low:find("not allowed", 1, true) then
            return nil, "cancelled", out
        end
        return nil, "failed", out
    end

    return out, nil, nil
end

local function on_browse()
    local path, err_kind, err_msg = pick_folder_finder()
    if path and input_dest then
        input_dest:set_text(path)
        set_status("Destination selected")
        return
    end

    if err_kind == "cancelled" then
        set_status("Folder picker cancelled")
    else
        set_status("Folder picker failed; paste path manually")
        if err_msg and err_msg ~= "" then set_status("Folder picker failed") end
    end
end

local function start_copy()
    if running then return end
    running = true

    clear_log_ui()
    set_status("Preparing...")

    local dest = expand_home(input_dest and input_dest:get_text() or "")
    dest = trim(dest)

    if dest == "" then
        append_ui_log("Total copied: 0")
        set_status("Error: destination is empty")
        running = false
        return
    end

    local ok_dir, dir_err = ensure_writable_dir(dest)
    if not ok_dir then
        append_ui_log("Total copied: 0")
        set_status("Error: cannot use destination")
        running = false
        return
    end

    local log_path = join_path(dest, "copy_log.txt")
    log_file = io.open(log_path, "a")
    if not log_file then
        append_ui_log("Total copied: 0")
        set_status("Error: cannot write log file")
        running = false
        return
    end

    append_file_log("=== VLC Playlist Copy started: " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===")
    append_file_log("Destination: " .. dest)

    local all_items = collect_playlist_items_flat()
    local total_items = #all_items

    if total_items == 0 then
        append_file_log("Playlist is empty (0 items).")
        append_file_log("Summary: total items=0, local files found=0, copied=0, skipped=0, errors=0")
        append_ui_log("Total copied: 0")
        set_status("Copied 0 / 0")
        close_log()
        running = false
        return
    end

    local local_files = {}
    for _, item in ipairs(all_items) do
        local uri = item.path or item.uri
        if type(uri) == "string" and is_local_media_uri(uri) then
            local src_path = file_uri_to_path(uri)
            if src_path and src_path ~= "" then
                table.insert(local_files, {
                    uri = uri,
                    src_path = src_path,
                    name = basename(src_path)
                })
            end
        end
    end

    local local_found = #local_files
    local copied = 0
    local skipped = 0
    local errors = 0
    local error_messages = {}

    if local_found == 0 then
        append_file_log("No local files found in current playlist (streams were ignored).")
        append_file_log("Summary: total items=" .. total_items .. ", local files found=0, copied=0, skipped=0, errors=0")
        append_ui_log("Total copied: 0")
        set_status("Copied 0 / 0")
        close_log()
        running = false
        return
    end

    for i, entry in ipairs(local_files) do
        local src = entry.src_path
        local dst = join_path(dest, entry.name)

        if file_exists(dst) then
            skipped = skipped + 1
            append_file_log(string.format("SKIPPED (%d/%d): exists -> %s", i, local_found, entry.name))
        else
            local ok_copy, copy_err = copy_file_safe(src, dst)
            if ok_copy then
                copied = copied + 1
                append_ui_log(entry.name)
                append_file_log(string.format("COPIED (%d/%d): %s", i, local_found, entry.name))
            else
                errors = errors + 1
                local em = string.format("ERROR (%d/%d): %s -> %s", i, local_found, entry.name, tostring(copy_err))
                error_messages[#error_messages + 1] = em
                append_file_log(em)
            end
        end

        set_status(string.format("Copied %d / %d", copied, local_found))
    end

    append_ui_log("Total copied: " .. copied)
    append_file_log("=== Summary ===")
    append_file_log("Total items: " .. total_items)
    append_file_log("Local files found: " .. local_found)
    append_file_log("Copied: " .. copied)
    append_file_log("Skipped: " .. skipped)
    append_file_log("Errors: " .. errors)

    if #error_messages > 0 then
        append_file_log("--- Error list ---")
        for _, e in ipairs(error_messages) do
            append_file_log(e)
        end
    end

    set_status(string.format("Copied %d / %d (done)", copied, local_found))
    close_log()
    running = false
end

function build_ui()
    dlg = vlc.dialog("Playlist Local File Copier")

    dlg:add_label("Destination folder:", 1, 1, GRID_COLS, 1)

    input_dest = dlg:add_text_input((os.getenv("HOME") or "") .. "/Desktop", 1, 2, GRID_COLS - 1, 1)
    dlg:add_button("Browse...", on_browse, GRID_COLS, 2, 1, 1)

    dlg:add_button("Copy", start_copy, 1, 3, 1, 1)

    label_status = dlg:add_label("Idle", 1, 4, GRID_COLS, 1)
    list_log = dlg:add_list(1, 5, GRID_COLS, 10)
end
