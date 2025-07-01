local M = {}

-- Función para crear buffer flotante scratch
local function open_floating_buffer()
	local buf = vim.api.nvim_create_buf(false, true) -- no listado, scratch

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

	local win = vim.api.nvim_open_win(buf, true, opts)

	-- Configuración del buffer
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true
	vim.bo[buf].filetype = "markdown"

	-- Configuración de la ventana
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].conceallevel = 2
	vim.wo[win].concealcursor = "n"

	-- Mapeo para cerrar la ventana con 'q'
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })

	return buf, win
end

local function run_gemini_streamed(prompt)
	local buf, win = open_floating_buffer()
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)

	local pending_chunks = {}
	local buf_ready = true -- buffer ya está listo

	-- Escribir líneas en el buffer (desbloqueando temporalmente)
	local function write_to_buf(lines)
		if not buf or not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		local ok = pcall(function()
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
			vim.bo[buf].modifiable = false
		end)
		if not ok then
			vim.notify("Error escribiendo en el buffer de Gemini", vim.log.levels.WARN)
		end
	end

	-- Procesar chunk recibido
	local function append_to_buf(data)
		if not data then
			return
		end
		vim.schedule(function()
			local lines = {}
			-- Separar líneas con patrón robusto
			for line in data:gmatch("([^\n]*)\n?") do
				table.insert(lines, line)
			end
			write_to_buf(lines)
		end)
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "⌛ Generando respuesta..." })
	vim.bo[buf].modifiable = false

	-- Iniciar proceso Gemini
	local handle = vim.loop.spawn("gemini", {
		args = { "-p", prompt },
		stdio = { nil, stdout, stderr },
	}, function()
		stdout:close()
		stderr:close()
		vim.schedule(function()
			if buf_ready and vim.api.nvim_buf_is_valid(buf) then
				local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				if #current == 1 and current[1]:find("Generando") then
					vim.bo[buf].modifiable = true
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "❌ No se recibió salida de Gemini." })
					vim.bo[buf].modifiable = false
				end
			end
		end)
	end)

	-- Leer salida en tiempo real
	stdout:read_start(function(err, data)
		if err then
			vim.schedule(function()
				vim.api.nvim_err_writeln("Error leyendo Gemini: " .. err)
			end)
			return
		end
		append_to_buf(data)
	end)
end

-- Prompt manual
function M.ask_prompt_streamed()
	vim.ui.input({ prompt = "Pregunta a Gemini: " }, function(input)
		if input and input ~= "" then
			run_gemini_streamed(input)
		end
	end)
end

-- Prompt desde selección visual
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
