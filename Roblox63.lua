--[[
    Custom Mesh + Jiggle Physics v3 (chỉ client - chỉ mình bạn nhìn thấy)
    - CHỈ HỖ TRỢ R6. Bật khi đang R15 -> thông báo "R15 not supported".
    - Giữ skin: part gốc vẫn còn (màu da BodyColors giữ nguyên), áo/quần CLASSIC
      (Shirt / Pants) được phủ lên mesh bằng các lớp texture. Mesh đã được map lại UV
      theo đúng template áo/quần classic của Roblox (585x559).
    - Jiggle: chỉ 2 ball ở torso, mô phỏng lò xo 3 trục trong không gian thế giới
      (theo chuyển động, xoay người, nhảy/đáp đất, nhịp bước chân), có squash/stretch.

    FILE MESH trong  workspace/meshes/  (7 file, nhớ GHI ĐÈ bằng bản mới):
        torso_body.mesh, ball_left.mesh, ball_right.mesh,
        leftarm.mesh, rightarm.mesh, leftleg.mesh, rightleg.mesh
    Hoặc điền Asset ID vào CONFIG.AssetIds.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

-- Dọn sạch bản script chạy trước đó (chạy lại script không bị chồng 2 lớp mesh/họa tiết cũ)
local env = (getgenv and getgenv()) or _G
if env.__CustomMeshJiggleCleanup then pcall(env.__CustomMeshJiggleCleanup) end
if player.Character then
	for _, ch in ipairs(player.Character:GetChildren()) do
		if ch.Name:sub(1, 11) == "CustomMesh_" then ch:Destroy() end
	end
end

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
local CONFIG = {
	LocalFolder = "meshes",

	-- Tự tải mesh từ GitHub (không cần tự bỏ file vào workspace).
	-- Điền link raw tới thư mục meshes, KẾT THÚC bằng dấu "/":
	--   https://raw.githubusercontent.com/<user>/<repo>/main/meshes/
	-- Để "" nếu muốn dùng file có sẵn trong workspace/meshes.
	BaseUrl = "https://raw.githubusercontent.com/skibidioile761/r63/main/meshes/",
	ForceRedownload = false,  -- true = luôn tải lại mesh mới (khi bạn vừa cập nhật mesh trên GitHub)

	AssetIds = { -- "rbxassetid://123456" (ưu tiên hơn file local)
		torso = "", ballleft = "", ballright = "",
		leftarm = "", rightarm = "", leftleg = "", rightleg = "",
	},

	-- true = KHÔNG cần file mesh: 2 ball là hình cầu có sẵn của Roblox (mịn, không bị ô vuông),
	--        thân/tay/chân giữ nguyên R6 gốc. false = dùng 7 file mesh như cũ.
	NoMeshFiles = false,
	-- Màu "áo ngực" phủ lên ball khi NoMeshFiles = true. nil = để trần (chỉ màu da)
	BraColor = Color3.fromRGB(15, 15, 15),

	Clothing = true,          -- phủ Classic Shirt / Pants lên mesh
	BallClothing = true,      -- false = 2 ball chỉ có màu da, không phủ họa tiết áo/quần (hết vòng tròn/hình lạ trên ball)
	JiggleEnabled = true,
	JiggleMultiplier = 1,     -- 0 = tắt, 1.5 = nảy mạnh hơn
	StepBounce = 0.8,         -- độ nảy theo nhịp bước chân khi chạy (0 = tắt)
	Breathing = 0.009,        -- chuyển động thở nhẹ khi đứng yên (0 = tắt)

	-- Ép màu da nếu vẫn bị đen, ví dụ: Color3.fromRGB(255, 204, 153). nil = dùng màu gốc
	SkinColor = nil,
}

-- Roblox chỉ bật alpha blending cho texture khi Transparency > 0.
-- Không có hack này, vùng trong suốt của áo/quần sẽ hiện ĐEN thay vì lộ màu da.
local LAYER_TRANSPARENCY = 0.001

-- inflate: độ phồng nhẹ của từng lớp để không bị z-fight (pants dưới, shirt trên)
local INFLATE = { pants = 1.012, shirt = 1.024 }

-- center = tâm bbox của mesh (dùng để phồng lớp áo đúng tâm)
local PIECES = {
	{ key = "torso",    file = "torso_body.mesh", part = "Torso",     layers = { "pants", "shirt" },
	  center = Vector3.new(0, -0.061, -0.02),   scale = Vector3.one, offset = Vector3.zero },
	{ key = "leftarm",  file = "leftarm.mesh",    part = "Left Arm",  layers = { "shirt" },
	  center = Vector3.new(0.013, 0.025, 0),    scale = Vector3.one, offset = Vector3.zero },
	{ key = "rightarm", file = "rightarm.mesh",   part = "Right Arm", layers = { "shirt" },
	  center = Vector3.new(-0.019, 0.026, 0),   scale = Vector3.one, offset = Vector3.zero },
	{ key = "leftleg",  file = "leftleg.mesh",    part = "Left Leg",  layers = { "pants" },
	  center = Vector3.new(-0.08, 0.18, 0.071), scale = Vector3.one, offset = Vector3.zero },
	{ key = "rightleg", file = "rightleg.mesh",   part = "Right Leg", layers = { "pants" },
	  center = Vector3.new(0.08, 0.18, 0.071),  scale = Vector3.one, offset = Vector3.zero },
}

-- 2 ball. Trục theo torso: X = ngang, Y = dọc, Z = trước/sau
-- freq  : tần số dao động riêng (Hz)      -> cao = cứng/nhanh, thấp = mềm/chậm
-- zeta  : hệ số tắt dần (0.1 nảy lâu ... 0.5 tắt nhanh)
-- maxOff: biên độ tối đa mỗi trục (studs)
-- tilt  : độ nghiêng theo độ lệch | squash: độ co giãn theo trục dọc
local BALLS = {
	{
		key = "ballleft", file = "ball_left.mesh", side = -1,
		center = Vector3.new(-0.575, 0.28, -0.649), scale = Vector3.one,
		sphereCenter = Vector3.new(-0.575, 0.28, -0.80), sphereSize = Vector3.new(1.2, 1.4, 1.3),
		freq = Vector3.new(3.4, 3.0, 3.6), zeta = Vector3.new(0.30, 0.24, 0.32),
		maxOff = Vector3.new(0.08, 0.15, 0.09), tilt = 0.35, squash = 0.14,
	},
	{
		key = "ballright", file = "ball_right.mesh", side = 1,
		center = Vector3.new(0.578, 0.28, -0.649), scale = Vector3.one,
		sphereCenter = Vector3.new(0.578, 0.28, -0.80), sphereSize = Vector3.new(1.2, 1.4, 1.3),
		freq = Vector3.new(3.5, 3.1, 3.7), zeta = Vector3.new(0.31, 0.25, 0.33), -- lệch nhẹ cho tự nhiên
		maxOff = Vector3.new(0.08, 0.15, 0.09), tilt = 0.35, squash = 0.14,
	},
}

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local enabled = false
local meshEdits = {}   -- mesh gắn trực tiếp vào part gốc
local extraParts = {}  -- các lớp áo/quần của thân-tay-chân
local balls = {}
local torsoRef, leftLegRef, rightLegRef, humRef = nil, nil, nil, nil
local lastLegDiff, lastLegDelta = 0, 0
local heartbeatConn = nil
local meshCache = {}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Custom Mesh", Text = text, Duration = 4 })
	end)
end

local function resolveMesh(key, file)
	if meshCache[key] then return meshCache[key] end

	local id = CONFIG.AssetIds[key]
	if type(id) == "string" and id ~= "" then
		meshCache[key] = id
		return id
	end

	local path = CONFIG.LocalFolder .. "/" .. file

	-- tải từ GitHub về workspace nếu chưa có (hoặc ForceRedownload)
	if CONFIG.BaseUrl ~= "" and not CONFIG.BaseUrl:find("USER/REPO", 1, true)
		and writefile and isfile and (CONFIG.ForceRedownload or not isfile(path)) then
		pcall(function()
			if makefolder and isfolder and not isfolder(CONFIG.LocalFolder) then
				makefolder(CONFIG.LocalFolder)
			end
			local data = game:HttpGet(CONFIG.BaseUrl .. file, true)
			if type(data) == "string" and #data > 100 and data:sub(1, 7) == "version" then
				writefile(path, data)
			end
		end)
	end

	local ok, result = pcall(function()
		if isfile and getcustomasset and isfile(path) then
			return getcustomasset(path)
		end
		return nil
	end)
	if ok and result then
		meshCache[key] = result
		return result
	end
	return nil
end

local function getTextures(char)
	local t = { shirt = "", pants = "" }
	if not CONFIG.Clothing then return t end
	local shirt = char:FindFirstChildOfClass("Shirt")
	local pants = char:FindFirstChildOfClass("Pants")
	if shirt and shirt.ShirtTemplate ~= "" then t.shirt = shirt.ShirtTemplate end
	if pants and pants.PantsTemplate ~= "" then t.pants = pants.PantsTemplate end
	return t
end

-- tạo 1 part hiển thị mesh (dùng cho lớp áo/quần và ball)
local function newMeshPart(name, meshId, textureId, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = meshId
	mesh.TextureId = textureId or ""
	mesh.Parent = part
	return part, mesh
end

-- Scale + Offset sao cho tâm `center` đứng yên khi phồng/co
local function setMeshScale(mesh, center, scale, offset)
	mesh.Scale = scale
	mesh.Offset = (offset or Vector3.zero) + center - center * scale
end

----------------------------------------------------------------------
-- CLEAR
----------------------------------------------------------------------
local function clear()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end

	for _, b in ipairs(balls) do
		for _, e in ipairs(b.entries) do
			if e.part then e.part:Destroy() end
		end
	end
	table.clear(balls)

	for _, p in ipairs(extraParts) do
		if p then p:Destroy() end
	end
	table.clear(extraParts)

	for _, e in ipairs(meshEdits) do
		pcall(function()
			if CONFIG.SkinColor and e.part and e.part.Parent then
				e.part.Color = e.origColor
			end
			if e.created then
				e.mesh:Destroy()
			elseif e.mesh and e.mesh.Parent then
				for prop, value in pairs(e.orig) do
					e.mesh[prop] = value
				end
			end
		end)
	end
	table.clear(meshEdits)

	torsoRef, leftLegRef, rightLegRef, humRef = nil, nil, nil, nil
end

----------------------------------------------------------------------
-- JIGGLE
----------------------------------------------------------------------
local TWO_PI = math.pi * 2
local SUBSTEP = 1 / 120

local function updateBallVisual(b, d)
	local def = b.def
	local c = def.center
	local rot = CFrame.Angles(d.Z * def.tilt, 0, -d.X * def.tilt)
	local c0 = CFrame.new(d) * CFrame.new(c) * rot * CFrame.new(-c)

	local s = 1 + math.clamp(d.Y * def.squash / 0.26, -1, 1) * def.squash
	local r = 1 / math.sqrt(s)
	local sv = Vector3.new(r, s, r)

	for _, e in ipairs(b.entries) do
		e.weld.C0 = c0
		if e.sphere then
			e.mesh.Scale = e.diam * sv
			e.mesh.Offset = e.pos
		else
			setMeshScale(e.mesh, c, def.scale * e.inflate * sv)
		end
	end

	local base = b.entries[1]
	if base and torsoRef then
		base.part.Color = CONFIG.SkinColor or torsoRef.Color
		base.part.Transparency = torsoRef.Transparency
	end
	for i = 2, #b.entries do
		b.entries[i].part.Transparency = math.max(torsoRef and torsoRef.Transparency or 0, LAYER_TRANSPARENCY)
	end
end

local function jiggleStep(dt)
	if dt <= 0 or not torsoRef or not torsoRef.Parent then return end
	dt = math.min(dt, 1 / 20)

	local cf = torsoRef.CFrame
	local mult = CONFIG.JiggleEnabled and CONFIG.JiggleMultiplier or 0

	-- nhịp bước chân: điểm đổi chiều của khoảng cách trước/sau giữa 2 chân = chạm đất
	local strike = 0
	if CONFIG.StepBounce > 0 and leftLegRef and rightLegRef and humRef then
		local diff = cf:PointToObjectSpace(leftLegRef.Position).Z - cf:PointToObjectSpace(rightLegRef.Position).Z
		local delta = diff - lastLegDiff
		if delta * lastLegDelta < 0 and math.abs(diff) > 0.5
			and humRef.MoveDirection.Magnitude > 0.1
			and humRef.FloorMaterial ~= Enum.Material.Air then
			strike = (diff > 0) and 1 or -1
		end
		if math.abs(delta) > 1e-4 then lastLegDelta = delta end
		lastLegDiff = diff
	end
	local speedFactor = 0
	if strike ~= 0 then
		local v = torsoRef.AssemblyLinearVelocity
		speedFactor = math.min(Vector3.new(v.X, 0, v.Z).Magnitude / 16, 1.5)
	end

	local breathe = CONFIG.Breathing * math.sin(os.clock() * 1.6)

	for _, b in ipairs(balls) do
		local def = b.def
		local c = def.center
		local target = cf:PointToWorldSpace(c)

		if not b.init or (target - b.P).Magnitude > 6 then
			b.P, b.V, b.prevT, b.init = target, Vector3.zero, target, true
		end

		local Vt = (target - b.prevT) / dt
		b.prevT = target

		-- xung lực khi chạm đất: bóng bị "dội" xuống rồi bật lại
		if strike ~= 0 and speedFactor > 0 then
			local kick = 3.0 * CONFIG.StepBounce * speedFactor
			b.V += -cf.UpVector * kick + cf.RightVector * (strike * def.side * 0.5 * speedFactor)
		end

		local k = Vector3.new(
			(TWO_PI * def.freq.X) ^ 2, (TWO_PI * def.freq.Y) ^ 2, (TWO_PI * def.freq.Z) ^ 2)
		local cd = Vector3.new(
			2 * def.zeta.X * TWO_PI * def.freq.X,
			2 * def.zeta.Y * TWO_PI * def.freq.Y,
			2 * def.zeta.Z * TWO_PI * def.freq.Z)

		local steps = math.max(1, math.ceil(dt / SUBSTEP))
		local h = dt / steps
		for _ = 1, steps do
			local dloc = cf:PointToObjectSpace(b.P) - c
			local vloc = cf:VectorToObjectSpace(b.V - Vt)
			local acc = -(k * dloc) - cd * vloc
			b.V += cf:VectorToWorldSpace(acc) * h
			b.P += b.V * h
		end

		-- giới hạn trong ellipsoid, khử vận tốc hướng ra ngoài
		local dloc = cf:PointToObjectSpace(b.P) - c
		local q = math.sqrt((dloc.X / def.maxOff.X) ^ 2 + (dloc.Y / def.maxOff.Y) ^ 2 + (dloc.Z / def.maxOff.Z) ^ 2)
		if q > 1 then
			dloc = dloc / q
			b.P = cf:PointToWorldSpace(c + dloc)
			local n = cf:VectorToWorldSpace(dloc).Unit
			local rel = b.V - Vt
			local out = rel:Dot(n)
			if out > 0 then
				b.V = b.V - n * out * 1.3 -- hơi nảy ngược lại
			end
		end

		local d = dloc * mult + Vector3.new(0, breathe * mult, 0)
		updateBallVisual(b, d)
	end
end

----------------------------------------------------------------------
-- APPLY
----------------------------------------------------------------------
local function apply(char)
	clear()
	if not char then return false end

	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	if not hum then return false end

	if hum.RigType == Enum.HumanoidRigType.R15 then
		notify("R15 not supported")
		return false
	end

	local tex = getTextures(char)
	local missing = {}

	-- 1) mesh gắn thẳng vào part gốc (giữ màu da) + lớp áo/quần phủ lên trên
	if CONFIG.NoMeshFiles then
		torsoRef = char:FindFirstChild("Torso")
		leftLegRef = char:FindFirstChild("Left Leg")
		rightLegRef = char:FindFirstChild("Right Leg")
	end

	for _, piece in ipairs(CONFIG.NoMeshFiles and {} or PIECES) do
		local part = char:FindFirstChild(piece.part)
		local meshId = resolveMesh(piece.key, piece.file)

		if part and part:IsA("BasePart") and meshId then
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			local created, orig = false, nil
			if mesh then
				orig = { MeshType = mesh.MeshType, MeshId = mesh.MeshId, TextureId = mesh.TextureId,
					Scale = mesh.Scale, Offset = mesh.Offset }
			else
				mesh = Instance.new("SpecialMesh")
				created = true
			end
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = meshId
			mesh.TextureId = ""
			setMeshScale(mesh, piece.center, piece.scale, piece.offset)
			mesh.Parent = part
			local origColor = part.Color
			if CONFIG.SkinColor then part.Color = CONFIG.SkinColor end
			table.insert(meshEdits, { part = part, mesh = mesh, created = created, orig = orig, origColor = origColor })

			for _, layer in ipairs(piece.layers) do
				if tex[layer] ~= "" then
					local lp, lm = newMeshPart("CustomMesh_" .. piece.key .. "_" .. layer,
						meshId, tex[layer], Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
					setMeshScale(lm, piece.center, piece.scale * INFLATE[layer], piece.offset)
					lp.Transparency = LAYER_TRANSPARENCY
					local w = Instance.new("Weld")
					w.Part0, w.Part1, w.C0 = part, lp, CFrame.identity
					w.Parent = lp
					lp.Parent = char
					table.insert(extraParts, lp)
				end
			end

			if piece.key == "torso" then torsoRef = part end
			if piece.key == "leftleg" then leftLegRef = part end
			if piece.key == "rightleg" then rightLegRef = part end
		else
			table.insert(missing, piece.key)
		end
	end

	-- 2) 2 ball (có jiggle): lớp da + lớp pants + lớp shirt
	local torso = char:FindFirstChild("Torso")
	for _, def in ipairs(BALLS) do
		local meshId = (not CONFIG.NoMeshFiles) and resolveMesh(def.key, def.file) or nil
		if CONFIG.NoMeshFiles and torso and torso:IsA("BasePart") then
			-- hình cầu có sẵn: lớp da + lớp "áo ngực" (nhích lên để lộ da ở viền dưới)
			local b = { def = def, entries = {}, P = torso.Position, V = Vector3.zero,
				prevT = torso.Position, init = false }
			local function addSphere(color, diam, pos)
				local p = Instance.new("Part")
				p.Name = "CustomMesh_" .. def.key
				p.Size = Vector3.one
				p.Color = color
				p.Material = torso.Material
				p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
				p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				local m = Instance.new("SpecialMesh")
				m.MeshType = Enum.MeshType.Sphere
				m.Parent = p
				local w = Instance.new("Weld")
				w.Part0, w.Part1, w.C0 = torso, p, CFrame.identity
				w.Parent = p
				p.Parent = char
				table.insert(b.entries, { part = p, mesh = m, weld = w, inflate = 1,
					sphere = true, diam = diam, pos = pos })
				return p
			end
			addSphere(CONFIG.SkinColor or torso.Color, def.sphereSize, def.sphereCenter)
			if CONFIG.BraColor then
				local bra = addSphere(CONFIG.BraColor, def.sphereSize * Vector3.new(1.03, 0.92, 1.03),
					def.sphereCenter + Vector3.new(0, 0.08, 0))
				bra.Transparency = LAYER_TRANSPARENCY
			end
			table.insert(balls, b)
		elseif torso and torso:IsA("BasePart") and meshId then
			local b = { def = def, entries = {}, P = torso.Position, V = Vector3.zero,
				prevT = torso.Position, init = false }

			local function addEntry(textureId, inflate, suffix)
				local p, m = newMeshPart("CustomMesh_" .. def.key .. suffix, meshId, textureId,
					(suffix == "") and (CONFIG.SkinColor or torso.Color) or Color3.new(1, 1, 1), torso.Material)
				if suffix ~= "" then p.Transparency = LAYER_TRANSPARENCY end
				setMeshScale(m, def.center, def.scale * inflate)
				local w = Instance.new("Weld")
				w.Part0, w.Part1, w.C0 = torso, p, CFrame.identity
				w.Parent = p
				p.Parent = char
				table.insert(b.entries, { part = p, mesh = m, weld = w, inflate = inflate })
			end

			addEntry("", 1, "")
			if CONFIG.BallClothing and tex.pants ~= "" then addEntry(tex.pants, INFLATE.pants, "_pants") end
			if CONFIG.BallClothing and tex.shirt ~= "" then addEntry(tex.shirt, INFLATE.shirt, "_shirt") end
			table.insert(balls, b)
		else
			table.insert(missing, def.key)
		end
	end

	if #missing > 0 then
		notify("Không load được: " .. table.concat(missing, ", ")
			.. "\nKiểm tra Asset ID / thư mục workspace/" .. CONFIG.LocalFolder)
	end

	if #meshEdits == 0 and #balls == 0 then
		return false
	end

	humRef = hum
	if leftLegRef and rightLegRef and torsoRef then
		lastLegDiff = torsoRef.CFrame:PointToObjectSpace(leftLegRef.Position).Z
			- torsoRef.CFrame:PointToObjectSpace(rightLegRef.Position).Z
		lastLegDelta = 0
	end
	heartbeatConn = RunService.Heartbeat:Connect(jiggleStep)
	return true
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local guiParent
do
	local ok, result = pcall(function() return gethui and gethui() end)
	guiParent = (ok and result) or player:WaitForChild("PlayerGui")
end

local old = guiParent:FindFirstChild("CustomMeshToggleGui")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CustomMeshToggleGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = guiParent

local button = Instance.new("TextButton")
button.Name = "Toggle"
button.Size = UDim2.fromOffset(46, 46)
button.Position = UDim2.new(0, 12, 1, -70)
button.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
button.AutoButtonColor = false
button.Text = "OFF"
button.TextColor3 = Color3.new(1, 1, 1)
button.TextSize = 14
button.Font = Enum.Font.GothamBold
button.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = button

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.new(1, 1, 1)
stroke.Transparency = 0.4
stroke.Thickness = 2
stroke.Parent = button

local function refreshButton()
	button.Text = enabled and "ON" or "OFF"
	button.BackgroundColor3 = enabled and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(180, 60, 60)
end

local function setEnabled(state)
	if state then
		enabled = apply(player.Character) and true or false
	else
		enabled = false
		clear()
	end
	refreshButton()
end

local dragging, moved = false, false
local dragStart, startPos

button.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		moved = false
		dragStart = input.Position
		startPos = button.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				if not moved then
					setEnabled(not enabled)
				end
			end
		end)
	end
end)

local connInput = UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragStart
		if delta.Magnitude > 6 then moved = true end
		if moved then
			local screen = screenGui.AbsoluteSize
			local size = button.AbsoluteSize
			local x = math.clamp(startPos.X.Offset + delta.X + startPos.X.Scale * screen.X, 0, screen.X - size.X)
			local y = math.clamp(startPos.Y.Offset + delta.Y + startPos.Y.Scale * screen.Y, 0, screen.Y - size.Y)
			button.Position = UDim2.fromOffset(x, y)
		end
	end
end)

local connChar = player.CharacterAdded:Connect(function(char)
	clear()
	if enabled then
		task.wait(1.5) -- đợi áo/quần load xong
		enabled = apply(char) and true or false
		refreshButton()
	end
end)

refreshButton()

env.__CustomMeshJiggleCleanup = function()
	enabled = false
	clear()
	connInput:Disconnect()
	connChar:Disconnect()
	screenGui:Destroy()
end
