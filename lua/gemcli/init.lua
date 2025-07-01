local M = {}

local function run_gemini_streamed(prompt)
	local buf = nil
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)

	vim.schedule(function()
		vim.cmd("vnew")
		buf = vim.api.nvim_get_current_buf()

		-- Asignar nombre
		vim.api.nvim_buf_set_name(buf, "gemini")

		-- Configurar buffer temporal
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		vim.bo[buf].modifiable = true

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "⌛ Generando respuesta..." })

		-- Bloquear después de mensaje inicial
		vim.bo[buf].modifiable = false
	end)

	local output = {}

	local function append_to_buf(data)
		if not data or not buf then
			return
		end
		vim.schedule(function()
			-- Desbloquear, escribir y volver a bloquear
			vim.bo[buf].modifiable = true

			local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			if #current == 1 and current[1]:find("Generando") then
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
			end

			for line in data:gmatch("[^\r\n]+") do
				table.insert(output, line)
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
			end

			vim.bo[buf].modifiable = false
		end)
	end

	local handle = vim.loop.spawn("gemini", {
		args = { "-p", prompt },
		stdio = { nil, stdout, stderr },
	}, function()
		stdout:close()
		stderr:close()
		handle:close()

		vim.schedule(function()
			if #output == 0 and buf then
				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "❌ No se recibió salida de Gemini." })
				vim.bo[buf].modifiable = false
			end
		end)
	end)

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
