local M = {}

function M.ask_prompt()
	vim.ui.input({ prompt = "Pregunta a Gemini: " }, function(input)
		if input and input ~= "" then
			local output = vim.fn.system({ "gemini", "-p", input })
			M.show_output(output)
		end
	end)
end

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
	local output = vim.fn.system({ "gemini", "-p", prompt })
	M.show_output(output)
end

function M.show_output(output)
	vim.cmd("vnew")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output or "", "\n"))
end

return M
