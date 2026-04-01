CODEX 自动分析与修改计划
生成时间: 2026-04-01 09:03 (Asia/Shanghai)

目的：对 APP 与 PC 端界面差异进行全面分析，生成可执行的修改方案并由 Codex 自动实施，提交到 codex/auto-refine-responsive 分支，触发自动部署并进行验证。

1) 仓库概览（已知）
- 远程: https://github.com/haifeng9527a-design/wangye-web.git
- 当前分支: codex/auto-refine-responsive
- 重要目录: lib (api, core, features, l10n, ui), web, android, ios, packages

2) 分析步骤（自动化流程）
- Step A: 全量扫描代码（列出关键页面与组件，优先级：教师中心、主导航、响应式布局相关组件）
- Step B: 生成修改方案（为每个目标文件写出修改要点与伪代码/patch）
- Step C: 由 Codex 应用修改（小步提交：每次修改只改单一模块并运行 lint/build）
- Step D: 将修改 commit 到 codex/auto-refine-responsive 并 push
- Step E: 检查远程 CI/Render 是否触发部署，抓取部署日志与网站快照
- Step F: 根据部署结果与视觉差异继续迭代或回滚

3) 优先改动清单（初稿）
- 教师中心页面（lib/features/.../teacher_center_page.dart）：调整布局断点、交互目标大小、卡片/列表在窄屏和宽屏的排列方式
- 全局样式/断点：在 ui 层新增响应式断点配置与辅助布局组件
- 触控/鼠标差异：为按钮/交互控件定义最小可点击区域、鼠标悬停样式和聚焦样式

4) 验证标准
- 本地 lint/build 无错误
- 自动化单元/集成测试通过（如有）或手动检查关键页面无崩溃
- 部署后主要页面在手机与桌面上都能正常显示，视觉差异在可接受范围内

接下来动作：我现在把此分析文件 commit 到 codex/auto-refine-responsive 并 push，然后正式让 Codex 分步执行 Step A->F（每步我会把 Codex 的输出、diff、commit、部署日志追加到桌面日志并在聊天回报）。
