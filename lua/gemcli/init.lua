local M = {}

local function read_all(handle, callback)
	local output = ""
	handle:read_start(function(err, data)
		assert(not err, err)
		if data then
			output = output .. data
		else
			callback(output)
		end
	end)
end

--- Ejecuta Gemini CLI de forma asíncrona
local function run_gemini(prompt, callback)
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)

	local handle
	handle = vim.loop.spawn("gemini", {
		args = { "-p", prompt },
		stdio = { nil, stdout, stderr },
	}, function()
		stdout:close()
		stderr:close()
		handle:close()
	end)

	read_all(stdout, function(output)
		callback(output)
	end)
end

--- Prompt directo
function M.ask_prompt()
	vim.ui.input({ prompt = "Pregunta a Gemini: " }, function(input)
		if input and input ~= "" then
			run_gemini(input, M.show_output)
		end
	end)
end

--- Prompt desde selección visual
function M.ask_from_visual()
	local _, ls, cs = unpack(vim.fn.getpos("'<"))
	local _, le, ce = unpack(vim.fn.getpos("'>"))
	local lines = vim.fn.getline(ls, le)

	if #lines == 0 then
		return
	end

	lines[#lines] = string.sub(lines[#lines], 1, ce)
	lines[1] = string.sub(lines[1], cs)
	local prompt = table.concat(lines, "\n")

	run_gemini(prompt, M.show_output)
end

--- Mostrar salida en nuevo split
function M.show_output(output)
	vim.schedule(function()
		vim.cmd("vnew")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output or "", "\n"))
	end)
end

return M
