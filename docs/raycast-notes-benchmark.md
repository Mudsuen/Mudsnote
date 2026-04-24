# Mudsnote 对标本机 Raycast Notes / Apple Notes 扩展

## 说明

本次本机可直接反编译和阅读的实现，不是 Raycast 原生闭源的 “Raycast Notes” 内核，而是本机安装的 Raycast `Apple Notes` 扩展源码与 sourcemap：

- `~/.config/raycast/extensions/8c7187e0-f64c-4dba-ba77-b1cb543256d6/package.json`
- `~/.config/raycast/extensions/8c7187e0-f64c-4dba-ba77-b1cb543256d6/index.js.map`
- `~/.config/raycast/extensions/8c7187e0-f64c-4dba-ba77-b1cb543256d6/menu-bar.js.map`
- `~/.config/raycast/extensions/8c7187e0-f64c-4dba-ba77-b1cb543256d6/view-selected-note.js.map`

Raycast 主程序里与 “Raycast Notes” 相关的本地资源只能看到入口素材，内部数据模型和实现细节不可直接读到。所以本次结论主要来自“Raycast 团队做笔记场景扩展时，公开交付出来的产品结构”。

## 现在的 Mudsnote 已经有的能力

相对一个最小可用版笔记工具，Mudsnote 当前已经具备不错的基础面：

- 全局热键快速捕获
- 浮动笔记窗口
- Markdown 富文本编辑
- 标签解析与补全
- 多目录保存和跨目录搜索
- 草稿持久化
- 最近文件列表
- 独立偏好设置

这意味着 Mudsnote 不需要补“能不能记笔记”这类基础功能，而应该重点补“检索效率、信息密度、动作闭环、多入口”。

## Raycast 扩展里最值得借鉴的部分

### 1. 数据层和动作层是分开的

Raycast 扩展把实现拆得很清楚：

- `useNotes.ts` 负责把底层数据源整理成统一 `NoteItem`
- `api.ts` 只负责 create/open/delete/restore/getBody 这类动作
- `index.tsx` / `menu-bar.tsx` / `view-selected-note.tsx` 只是不同入口的展示层

对 Mudsnote 的启发：

- 现在 `NoteStore` 已经承担了存储层，但“动作”和“视图状态”仍偏耦合
- 下一步适合把“搜索索引 / 最近项 / 标签统计 / 链接关系”继续沉到核心层，把窗口控制器只保留 UI 逻辑

### 2. 列表项的信息密度很高，但不是靠大段正文

Raycast 列表不是只显示标题 + 摘要，而是叠了很多轻量元数据：

- 文件夹
- 账号
- 修改时间
- checklist 状态
- tags
- links / backlinks
- shared / locked

对 Mudsnote 的启发：

- 现有搜索结果只有标题、snippet、路径，密度偏低
- 可以把 tags、目录、修改时间、是否收藏/置顶、是否有任务项等变成 accessory 级信息
- 这类信息比“多显示两行正文”更有筛选价值

### 3. 不是一个入口，而是一组入口

Raycast 同时提供：

- 搜索列表
- 新建笔记
- 菜单栏最近/置顶
- 查看当前选中笔记
- 给已有笔记追加文本

对 Mudsnote 的启发：

- Mudsnote 现在强项是“快速新建”，弱项是“回到已有笔记继续处理”
- 需要从单一 capture 工具，升级成 capture + reopen + review + append 的完整闭环

### 4. 详情视图和动作面板做得比编辑页更重要

Raycast 的详情页做了三件事：

- 把 HTML/富文本统一转成 Markdown 预览
- 把元数据单独展示，而不是塞进正文
- 所有后续动作都挂在统一动作面板里

对 Mudsnote 的启发：

- Mudsnote 不一定先做复杂多栏界面，但应该先做“只读详情/预览态”
- 搜索结果点开后，不一定直接进入编辑；先看详情，再决定打开、复制、移动、追加内容，效率更高

### 5. 菜单栏入口非常克制，只做高频动作

Raycast 菜单栏只保留：

- 最近/置顶
- 新建
- 配置

对 Mudsnote 的启发：

- 当前菜单项已经接近这个方向
- 下一步不应该把菜单栏做成迷你编辑器，而应该继续保持“最近项 + pinned + 快速动作”的轻面板

### 6. 深链接和“打开方式分离”很重要

Raycast 扩展区分：

- 在宿主应用中打开
- 在独立窗口中打开
- 复制 URL
- 复制纯文本 / HTML / Markdown

对 Mudsnote 的启发：

- 同一条笔记，应该支持“快速预览 / 原位编辑 / 新窗口打开 / Finder 定位 / 复制 Markdown 路径”
- 行为分离后，搜索结果不会只剩一个“打开”按钮

## 不建议照搬的部分

### 1. 直接查 Apple Notes SQLite

Raycast 之所以能高性能拿到 tags、links、backlinks，是因为 Apple Notes 的数据库结构已经在那里。

Mudsnote 是 Markdown 文件型产品，不应该直接模仿这条实现路径。更合适的做法是：

- 维持 Markdown 文件作为真源
- 自建轻量索引缓存
- 把 tags / backlinks / task state 等派生信息增量索引出来

### 2. AI 相关笔记推荐

Raycast 里有“Find Related Notes”，但这是锦上添花，不是当前阶段的主线。

在 Mudsnote 里，先把 deterministic 的搜索、标签、链接关系做扎实，比先上 AI 更对。

## 建议迭代计划

### P0：把“快速捕获工具”补成“可持续使用的笔记工具”

目标：提高已有能力的完成度，不改产品方向。

1. 搜索结果增加 accessory 信息：标签、目录、修改时间、任务状态
2. 在最近列表和搜索列表里支持置顶/收藏
3. 给笔记提供只读详情预览，而不是所有入口都直接进编辑态
4. 增加常见动作：Finder 定位、复制文件路径、复制 Markdown、在新窗口打开

### P1：补上 Raycast 风格的多入口闭环

目标：让“新建、回看、追加、继续处理”更顺。

1. 新增菜单栏 recent + pinned 分区
2. 支持“追加到最近笔记/指定笔记”
3. 支持从当前剪贴板或当前选中文本快速建笔记
4. 给搜索窗口加入更完整的键盘动作和动作面板

### P2：建立自己的轻量索引层

目标：摆脱全量扫盘搜索，给高级能力打基础。

1. 为标题、正文、标签建立本地索引缓存
2. 增量更新最近改动文件，而不是每次全量遍历目录
3. 在索引中派生 task 计数、backlink、出链、最近访问时间
4. 把搜索排序从“标题/正文简单打分”升级为“标题命中 + 标签命中 + 最近使用 + 收藏权重”

### P3：围绕 Markdown 文件做关系能力

目标：做出区别于普通 capture 工具的长期价值。

1. 支持 `[[wikilink]]` 或标准 Markdown 链接的出链/反链
2. 支持按标签、按目录、按任务状态的过滤视图
3. 支持 pinned note、daily note、inbox note 等轻工作流
4. 支持把笔记当作项目面板来浏览，而不是只有单文件编辑

## 推荐优先级

如果只做一轮，我建议顺序是：

1. P0-1 搜索结果元数据增强
2. P0-3 只读详情预览
3. P1-1 菜单栏 recent/pinned 分区
4. P2-1 轻量索引缓存

原因很简单：

- 这四项直接提升“找得到”和“回得去”
- 它们都能复用当前 Mudsnote 的文件型存储
- 不需要先引入复杂同步、数据库或 AI

## 一句话结论

Raycast 在笔记场景里最值得学的不是视觉，而是结构：数据层薄、动作层清、入口多、列表元数据密、详情页和动作面板强。Mudsnote 下一轮最该补的是“检索与回访闭环”，不是继续堆编辑器功能。
