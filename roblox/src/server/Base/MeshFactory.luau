--!nonstrict
-- MeshFactory: turns the packed Blender geometry in Shared/Data/MeshData into MeshPart templates
-- at server boot, using EditableMesh -> CreateDataModelContentAsync -> CreateMeshPartAsync.
-- Data-model content replicates to clients like any instance, so the whole game gets real meshes
-- with zero uploads. If the experience has not enabled "Allow Mesh / Image APIs" (Game Settings >
-- Security, owner must be ID-verified) the factory reports unavailable and everything falls back
-- to the generated part-built models.
--
-- Templates are written to ReplicatedStorage.Assets.Meshes.<Id>. Each is a Model that keeps the
-- part-built template's Root (pivot), Trigger and attributes, with the visual parts replaced by one
-- MeshPart per material group. Behaviour attributes (Spike, Paddle, Jaw, Head, Door, Flame, Blade,
-- Vent) are copied onto the MeshParts so Traps/Turrets code works unchanged.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MeshIndex = require(Shared.Data.MeshData)

local MeshFactory = {
	Available = false,
	Reason = "not started",
	Built = {},
}

local ROOT_OFFSET = 0.1 -- the Root part centre sits 0.1 above the ground plane in every template

------------------------------------------------------------------------------------------------
-- base64 -> buffer
------------------------------------------------------------------------------------------------

local DECODE = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #alphabet do
		DECODE[string.byte(alphabet, i)] = i - 1
	end
end

local function fromBase64(text: string): buffer
	local len = #text
	local pad = 0
	if string.byte(text, len) == 61 then
		pad += 1
	end
	if string.byte(text, len - 1) == 61 then
		pad += 1
	end
	local outLen = (len // 4) * 3 - pad
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, len, 4 do
		local a, b, c, d = string.byte(text, i, i + 3)
		local n = bit32.lshift(DECODE[a] or 0, 18)
			+ bit32.lshift(DECODE[b] or 0, 12)
			+ bit32.lshift(DECODE[c] or 0, 6)
			+ (DECODE[d] or 0)
		if o < outLen then
			buffer.writeu8(out, o, bit32.band(bit32.rshift(n, 16), 255))
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(n, 8), 255))
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, bit32.band(n, 255))
		end
		o += 3
	end
	return out
end

------------------------------------------------------------------------------------------------
-- Mesh building
------------------------------------------------------------------------------------------------

local function buildEditable(group)
	local em = AssetService:CreateEditableMesh()
	if not em then
		return nil, "CreateEditableMesh returned nil (memory budget or permission)"
	end
	local vb = fromBase64(group.vertices)
	local tb = fromBase64(group.triangles)
	local vertexIds = table.create(group.vertexCount)
	local normalIds = table.create(group.vertexCount)
	for i = 0, group.vertexCount - 1 do
		local base = i * 9
		local x = buffer.readi16(vb, base) / 256
		local y = buffer.readi16(vb, base + 2) / 256
		local z = buffer.readi16(vb, base + 4) / 256
		local nx = buffer.readi8(vb, base + 6) / 127
		local ny = buffer.readi8(vb, base + 7) / 127
		local nz = buffer.readi8(vb, base + 8) / 127
		vertexIds[i + 1] = em:AddVertex(Vector3.new(x, y, z))
		normalIds[i + 1] = em:AddNormal(Vector3.new(nx, ny, nz))
	end
	for i = 0, group.triangleCount - 1 do
		local base = i * 6
		local a = buffer.readu16(tb, base) + 1
		local b = buffer.readu16(tb, base + 2) + 1
		local c = buffer.readu16(tb, base + 4) + 1
		local face = em:AddTriangle(vertexIds[a], vertexIds[b], vertexIds[c])
		em:SetFaceNormals(face, { normalIds[a], normalIds[b], normalIds[c] })
	end
	return em
end

local function bake(em): (Content?, string?)
	local result, content = AssetService:CreateDataModelContentAsync(Content.fromObject(em))
	if result ~= Enum.CreateContentResult.Success then
		return nil, "CreateDataModelContentAsync: " .. tostring(result)
	end
	return content, nil
end

local function makeMeshPart(group): (MeshPart?, string?)
	local em, err = buildEditable(group)
	if not em then
		return nil, err
	end
	local content, bakeErr = bake(em)
	em:Destroy()
	if not content then
		return nil, bakeErr
	end
	local part = AssetService:CreateMeshPartAsync(content, {
		CollisionFidelity = Enum.CollisionFidelity.Box,
		RenderFidelity = Enum.RenderFidelity.Automatic,
	})
	part.Name = group.name
	part.Anchored = true
	part.CanCollide = group.collide
	part.CanQuery = true
	part.CanTouch = false
	part.Color = Color3.fromRGB(group.color[1], group.color[2], group.color[3])
	part.Material = Enum.Material[group.material] or Enum.Material.SmoothPlastic
	part.Transparency = group.transparency or 0
	part.CastShadow = true
	if group.theme then
		part:SetAttribute("ThemeKey", group.theme)
	end
	for key, value in group.attrs do
		part:SetAttribute(key, value)
	end
	return part, nil
end

-- Builds one template Model for a mesh entry. `base` is the part-built template to keep Root,
-- Trigger and attributes from (may be nil for hub props).
local function buildTemplate(id: string, data, base: Model?): (Model?, string?)
	local model: Model
	local root: BasePart
	if base then
		model = base:Clone()
		local primary = model.PrimaryPart
		if not primary then
			return nil, "template has no PrimaryPart"
		end
		root = primary
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child ~= root and child.Name ~= "Trigger" then
				child:Destroy()
			elseif child:IsA("PointLight") then
				child:Destroy()
			end
		end
	else
		model = Instance.new("Model")
		model.Name = id
		root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(data.cells[1] * 4, 0.2, data.cells[2] * 4)
		root.Transparency = 1
		root.CanCollide = false
		root.CanTouch = false
		root.CanQuery = false
		root.Anchored = true
		root.CFrame = CFrame.new(0, ROOT_OFFSET, 0)
		root.Parent = model
		model.PrimaryPart = root
		model:SetAttribute("PieceId", id)
	end
	model.Name = id
	model:SetAttribute("Mesh", true)

	local rootCFrame = root.CFrame
	for _, group in data.groups do
		local part, err = makeMeshPart(group)
		if not part then
			model:Destroy()
			return nil, err
		end
		part.CFrame = rootCFrame * CFrame.new(group.center[1], group.center[2] - ROOT_OFFSET, group.center[3])
		part.Parent = model
	end
	for name, pos in data.attachments do
		local existing = root:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.CFrame = CFrame.new(pos[1], pos[2] - ROOT_OFFSET, pos[3])
		attachment.Parent = root
	end
	for index, light in data.lights do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Light" .. index
		attachment.CFrame = CFrame.new(light.position[1], light.position[2] - ROOT_OFFSET, light.position[3])
		attachment.Parent = root
		local pointLight = Instance.new("PointLight")
		pointLight.Color = Color3.fromRGB(light.color[1], light.color[2], light.color[3])
		pointLight.Brightness = light.brightness
		pointLight.Range = light.range
		pointLight.Shadows = false
		pointLight.Parent = attachment
	end
	return model, nil
end

------------------------------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------------------------------

function MeshFactory.build()
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local pieces = assets:WaitForChild("Pieces")
	local folder = assets:FindFirstChild("Meshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Meshes"
		folder.Parent = assets
	end

	-- Probe once so a missing permission fails fast with a clear message.
	local probeOk, probeErr = pcall(function()
		local em = AssetService:CreateEditableMesh()
		if not em then
			error("CreateEditableMesh returned nil")
		end
		em:Destroy()
	end)
	if not probeOk then
		MeshFactory.Available = false
		MeshFactory.Reason = tostring(probeErr)
		warn(
			"[MeshFactory] runtime meshes unavailable, using part-built models. Enable Game Settings > Security > Allow Mesh / Image APIs. ("
				.. MeshFactory.Reason
				.. ")"
		)
		return false
	end

	local started = os.clock()
	local built, failed = 0, 0
	for _, id in MeshIndex do
		local module = Shared.Data.MeshData:FindFirstChild(id)
		if not module then
			continue
		end
		local okData, data = pcall(require, module)
		if not okData then
			warn("[MeshFactory] bad mesh module " .. id .. ": " .. tostring(data))
			continue
		end
		local base = data.placeable and pieces:FindFirstChild(id) or nil
		local ok, model, err = pcall(buildTemplate, id, data, base)
		if ok and model then
			model.Parent = folder
			MeshFactory.Built[id] = model
			built += 1
		else
			failed += 1
			warn(("[MeshFactory] %s failed: %s"):format(id, tostring(ok and err or model)))
			if failed >= 3 and built == 0 then
				MeshFactory.Available = false
				MeshFactory.Reason = tostring(ok and err or model)
				warn("[MeshFactory] giving up on runtime meshes: " .. MeshFactory.Reason)
				return false
			end
		end
		if built % 6 == 0 then
			task.wait()
		end
	end
	MeshFactory.Available = built > 0
	MeshFactory.Reason = built > 0 and "ok" or "nothing built"
	print(
		("[MeshFactory] built %d mesh templates (%d failed) in %.0f ms"):format(
			built,
			failed,
			(os.clock() - started) * 1000
		)
	)
	return MeshFactory.Available
end

function MeshFactory.template(id: string): Model?
	return MeshFactory.Built[id]
end

function MeshFactory.init()
	if RunService:IsClient() then
		return
	end
	-- Build synchronously so the hub and first bases already use meshes; a few hundred ms.
	MeshFactory.build()
end

return MeshFactory
