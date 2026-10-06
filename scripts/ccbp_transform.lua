-- 蓝图变换数学: 旋转/吸附/施工步骤计算
-- 客户端投影渲染与服务器施工共用, 保证两端结果完全一致
local TransformCC = {}

-- 与 Base Projection 的 BSPJRotate 相同的旋转约定(极坐标法, 角度制, 屏幕坐标系 z 向下)
function TransformCC.RotateOffset(x, z, angle)
    if angle == 0 then
        return x, z
    end
    while angle < 0 do
        angle = angle + 360
    end
    while angle >= 360 do
        angle = angle - 360
    end
    local rau = math.sqrt(x * x + z * z)
    if rau == 0 then
        return x, z
    end
    local theta = math.acos(x / rau) / 3.14159265 * 180
    if z < 0 then
        theta = 360 - theta
    end
    theta = (theta + angle) / 180 * 3.14159265
    return rau * math.cos(theta), rau * math.sin(theta)
end

function TransformCC.Snap(v, step)
    step = step or 0.5
    return math.floor(v / step + 0.5) * step
end

-- 把蓝图从"蓝图坐标"(相对 origin 的偏移)变换到世界坐标
-- bp.structures 内 x/z 是相对蓝图原点的偏移; q 为 0..3 (每档 90°)
-- 返回绝对坐标的施工步骤数组: { prefab, x, z, rot, scale, layer }
function TransformCC.ComputeSteps(bp, ox, oz, q)
    local angle = (math.floor(q) % 4) * 90
    local steps = {}
    for i, s in ipairs(bp.structures) do
        local dx, dz = TransformCC.RotateOffset(s.x, s.z, angle)
        steps[#steps + 1] = {
            prefab = s.prefab,
            x = ox + dx,
            z = oz + dz,
            rot = ((s.rot or 0) + angle) % 360,
            scale = s.scale,
            layer = s.layer,
        }
    end
    return steps
end

return TransformCC
