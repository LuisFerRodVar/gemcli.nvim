local M = {}
M.model = "gemini-2.5-pro" -- Modelo predeterminado
M.buf = nil
M.win = nil
local already_warned = false

function M.toggle_model()
	if M.model == "gemini-2.5-pro" then
		M.model = "gemini-2.5-flash"
	else
		M.model = "gemini-2.5-pro"
	end
	vim.notify("🔁 Modelo cambiado a: " .. M.model, vim.log.levels.INFO)
end

-- Crear y mostrar el buffer flotante
local function open_floating_buffer()
	-- Cerrar ventana anterior si existe
	if M.win and vim.api.nvim_win_is_valid(M.win) then
		vim.api.nvim_win_close(M.win, true)
	end

	-- Crear nuevo buffer si es inválido
	if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
		M.buf = vim.api.nvim_create_buf(false, true)
	end

	local width = math.floor(vim.o.columns * 0.7)
	local height = math.floor(vim.o.lines * 0.5)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local opts = {
		style = "minimal",
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = "rounded",
	}

	M.win = vim.api.nvim_open_win(M.buf, true, opts)

	vim.bo[M.buf].buftype = "nofile"
	vim.bo[M.buf].bufhidden = "hide"
	vim.bo[M.buf].swapfile = false
	vim.bo[M.buf].filetype = "markdown"

	vim.wo[M.win].number = false
	vim.wo[M.win].relativenumber = false
	vim.wo[M.win].conceallevel = 2
	vim.wo[M.win].concealcursor = "n"

	vim.api.nvim_buf_set_keymap(
		M.buf,
		"n",
		"q",
		"<cmd>lua require'gemcli'.hide()<CR>",
		{ noremap = true, silent = true }
	)

	-- Mensaje visible de prueba
	vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, { "# Esperando respuesta de Gemini..." })

	return M.buf, M.win
end

function M.hide()
	if M.win and vim.api.nvim_win_is_valid(M.win) then
		vim.api.nvim_win_close(M.win, true)
		M.win = nil
	end
end

function M.show()
	if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
		open_floating_buffer()
	end
end

local function run_gemini_streamed(prompt)
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)
	local shown = false

	vim.notify("⌛ Generando respuesta con Gemini...", vim.log.levels.INFO)

	local function write_to_buf(lines)
		if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
			return
		end
		local ok = pcall(function()
			vim.bo[M.buf].modifiable = true
			vim.api.nvim_buf_set_lines(M.buf, -1, -1, false, lines)
			vim.bo[M.buf].modifiable = false
		end)
		if not ok then
			vim.notify("Error escribiendo en el buffer de Gemini", vim.log.levels.WARN)
		end
	end

	local function append_to_buf(data)
		vim.schedule(function()
			-- Abrir buffer al primer intento, sin importar si el contenido está vacío
			if not shown then
				open_floating_buffer()
				vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, {})
				vim.bo[M.buf].modifiable = false
				shown = true
			end

			if not data or data == "" then
				return
			end

			local lines = {}
			for line in data:gmatch("([^\n]*)\n?") do
				table.insert(lines, line)
			end
			write_to_buf(lines)
		end)
	end

	local handle = vim.loop.spawn("gemini", {
		args = { "-p", prompt, "-m", M.model },
		stdio = { nil, stdout, stderr },
	}, function()
		stdout:close()
		stderr:close()
		vim.schedule(function()
			if shown and vim.api.nvim_buf_is_valid(M.buf) then
				local current = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
				if #current == 0 then
					vim.bo[M.buf].modifiable = true
					vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, { "❌ No se recibió salida de Gemini." })
					vim.bo[M.buf].modifiable = false
				end
			end
		end)
	end)

	stderr:read_start(function(err, data)
		if err then
			vim.schedule(function()
				vim.api.nvim_err_writeln("Error leyendo stderr de Gemini: " .. err)
			end)
			return
		end

		if data and data ~= "" then
			vim.schedule(function()
				-- Detectar error de cuota u otros errores
				if data:match("Quota exceeded") then
					vim.notify("⚠️ Límite diario de Gemini alcanzado.", vim.log.levels.WARN)
					M.hide()
					if handle and handle:is_active() then
						handle:kill("sigterm") -- O "sigint"
					end
				else
					append_to_buf(data)
				end
			end)
		end
	end)
end

function M.ask_prompt_streamed()
	vim.ui.input({ prompt = "Pregunta a Gemini: " }, function(input)
		if input and input ~= "" then
			run_gemini_streamed(input)
		end
	end)
end

function M.ask_visual_streamed()
	local _, ls, cs = unpack(vim.fn.getpos("'<"))
	local _, le, ce = unpack(vim.fn.getpos("'>"))
	local lines = vim.fn.getline(ls, le)
	if #lines == 0 then
		return
	end
	lines[#lines] = string.sub(lines[#lines], 1, ce)
	lines[1] = string.sub(lines[1], cs)
	local prompt = table.concat(lines, "\n")
	run_gemini_streamed(prompt)
end

return M
