# DST Construction Cannon 建筑大炮

一个**独立实现**的 Don't Starve Together MOD:读取 Base Projection 格式的 JSON 蓝图,用一门"建筑大炮"自动施工,体验类似 Minecraft Create 的 Schematicannon。

> 本 MOD **不是** Base Projection 的 fork,不依赖其任何代码 / prefab / UI / 快捷键,唯一的交集是**兼容它的 JSON 蓝图文件格式**。

```
蓝图 JSON → 服务器蓝图库 → 莎草纸刻录 → 蓝图物品 → 放置投影(鼠标)
   → 右键确认 → WASD 微调 / Q/E 旋转(锁定玩家) → 最终确认
   → 服务器重新验证 → 施工队列 → 大炮一发一发炮建
```

---

## 一、安装

1. 把整个 `dps` 文件夹复制(或做目录联接)到 DST 的 mods 目录:
   `Steam/steamapps/common/Don't Starve Together/mods/dps`
2. 游戏内 → 模组 → 服务器模组(或客户端模组) → 启用「建筑大炮 Construction Cannon」→ 创建/进入世界。

## 二、蓝图文件放在哪

引擎没有列目录 API(原版 Base Projection 也是手输文件名),所以本 MOD 提供三种方式,加载时按顺序尝试两个目录:

| 目录 | 说明 |
|---|---|
| `游戏根目录/unsafedata/` | **Base Projection 约定目录**(和 exe 同级),文件直接兼容 |
| `mods/dps/blueprints/` | 本 MOD 自带目录,已附示例 `sample_camp.json` |

1. **索引文件(推荐)**:在 `unsafedata/ccbp_index.json` 写 `["我的基地1.json", "我的基地2.json"]`,世界加载时自动全部读入。
2. **游戏内手动读取**:蓝图库界面底部输入文件名 → 「读取」(不用 `.json` 后缀也行)。
3. **控制台命令**(需在模组配置里开「调试命令」):`c_ccbp_load("文件名")`。

蓝图格式 = Base Projection 原样:顶层 `{x, y, z, name, data:[...]}`,`data` 每项含 `prefab / x / y / z / rotation(角度) / scale / layer / build / bank / anim`。顶层 x/z 是录制原点,MOD 会自动换算成相对偏移。

**可施工的 prefab 白名单**:有 placer 的配方(火堆、冰箱、锅、箱子、农场、科学机器……)、`*_item` 部署套件(墙)、以及所有 `wall_*` / `fence_*`。生物、物品等会被校验器自动过滤。

## 三、游戏内流程

1. **造大炮**:建筑栏 → 建筑大炮(齿轮×2 + 木板×2 + 石砖×4,科学机器解锁)。
2. **放材料**:把施工材料塞进大炮货舱(LMB 打开),或放进大炮附近的箱子(取料半径可配置,默认 6)。
3. **刻蓝图**:右键大炮 → 「蓝图库」→ 选蓝图 → 「刻录蓝图」(消耗 莎草纸×1)→ 获得建筑蓝图。
4. **放投影**:右键背包里的蓝图 → 「放置投影」→ 投影跟随鼠标(绿色半透明)。
5. **微调**:右键确认位置 → 进入微调模式(玩家锁定):
   - `WASD` 移动(按 DST 摄像机方向),`Shift` 慢速
   - `Q/E` 绕蓝图原点旋转 90°/档
   - 右键或「确认施工」按钮 → 提交;`ESC` 取消
6. **自动施工**:大炮按配置间隔一发一发地炮建(材料不足自动进入 `等待材料` 状态,补料后继续);锤子可拆大炮(返还齿轮)。

## 四、8 阶段验收清单(按开发顺序测试)

| 阶段 | 测试内容 | 预期 |
|---|---|---|
| 1. MOD 启动 | 启用 MOD 建世界 | 无报错;服务器日志出现 `[CCBP] 蓝图库加载完成: 1 张可用`(示例蓝图) |
| 2. JSON 读取 | 把自己的 JSON 放进 `unsafedata/` 并写进 `ccbp_index.json`,重进世界(或开调试后 `c_ccbp_reload`) | `c_ccbp_list` 能列出;文件名错误/格式错误时日志有明确报错 |
| 3. 蓝图浏览 | 右键大炮 | 打开蓝图库,列表显示名称与结构数 |
| 4. 蓝图刻录 | 背包放 1 莎草纸 → 点「刻录蓝图」 | 莎草纸消失,获得「蓝图·<名称>」;没莎草纸时顶部提示报错 |
| 5. 蓝图物品 | 检查物品、存读档 | 图标为莎草纸、名字带蓝图名;存读档后仍在且可用 |
| 6. 投影 | 右键蓝图 → 放置投影 | 绿色半透明 ghost 跟随鼠标,布局与原基地一致;栅栏薄/厚朝向正确;无法预览的结构会计数提示 |
| 7. 确认模式 | 右键确认位置 | 玩家无法移动/攻击;WASD 摄像机相对移动;Q/E 旋转(绕原点);Shift 慢速;ESC 退出 |
| 8. 建筑施工 | 确认施工 | 大炮逐发建造(飞行特效+落地扬尘);材料不足时说「等待材料」补料即续;占位/水面位置自动跳过;结束后报成功/跳过数;施工中右键大炮可「取消施工」 |

调试命令(模组配置开启后):`c_ccbp_reload()` `c_ccbp_list()` `c_ccbp_load("文件名")` `c_ccbp_give(["id"])`。报错请看 `client_log.txt` / 服务器日志里 `[CCBP]` 前缀与 Lua 堆栈。

## 五、模块结构(编码规则:modmain 只做注册)

```
modmain.lua                  仅注册: prefab/组件/动作/RPC/配方/选项 (~120行)
modinfo.lua
scripts/
  ccbp_config.lua            常量与模组选项
  ccbp_transform.lua         旋转/吸附/步骤计算(客户端渲染与服务器施工共用同一份数学)
  ccbp_validator.lua         Base Projection JSON → 内部蓝图格式 + 白名单校验
  ccbp_jsonloader.lua        unsafedata/ 与 blueprints/ 读取 + index 索引
  ccbp_netdata.lua           服务器→客户端 分块传输(CLIENT_MOD_RPC, 逐结构分块)
  ccbp_actions.lua           动作处理逻辑(放置/浏览/取消)
  ccbp_rpc.lua               RPC 处理逻辑(全部入参按不可信数据校验)
  ccbp_ghosts.lua            客户端 ghost: 客户端方式 SpawnPrefab 真实建筑+去物理+半透明
  ccbp_placement.lua         放置/微调状态机(输入拦截、摄像机相对 WASD、QE 旋转)
  ccbp_uiscreens.lua         蓝图库浏览器 + 施工确认面板
  ccbp_debug.lua             调试命令
  components/
    ccbp_store.lua           蓝图库(世界组件, 服务器保存完整数据并随存档持久化)
    constructioncannon.lua   施工队列状态机 + 材料系统(仅服务器)
    construction_blueprint.lua 蓝图物品组件(只存 blueprint_id)
  prefabs/
    construction_cannon.lua  建筑大炮(原版 boat_cannon 模型/音效, 零新美术)
    projection_blueprint.lua 蓝图物品(原版莎草纸外观)
    ccbp_fx.lua              客户端炮弹飞行特效(纯本地实体)
```

## 六、架构规则落实情况

- **网络规则**:客户端只做 UI/投影/ghost/特效;蓝图保存、合法性检查(可站立地面、0.8 单位内无建筑、大炮射程)、材料检查、真正建筑生成全部在服务器;RPC 入参全部类型/范围校验,蓝图物品只保存 `blueprint_id`。
- **性能规则**:服务器不逐帧移动炮弹——开炮瞬间设置一次 netvar(坐标+序号),客户端各自生成本地炮弹特效;投影为客户端本地实体;施工队列用周期任务逐发执行,状态机 `IDLE / CHECKING / WAITING_MATERIAL / BUILDING / COMPLETED / ERROR`。
- **美术规则**:全部原版资源(boat_cannon 模型、monkeyisland/cannon/shoot 音效、cannonball_rock 弹体、collapse_small 扬尘、莎草纸物品),零新美术。

## 七、已知限制(当前版本)

- 大炮发射时不自动转向目标(纯朝向旋转需要额外校准,后续可加)。
- 施工队列不跨存档(读档后大炮回到 IDLE,蓝图与已建建筑都保留)。
- 结构间距 < 0.8 单位或落在已有建筑上时会被跳过(计入「跳过」数)。
- 船上施工未做平台适配(落在甲板上能生成,但不会随船移动)。
- 超大蓝图(上千结构)投影期间可能掉帧;蓝图数据分块传输,大蓝图首次投影有 1~2 秒加载。
