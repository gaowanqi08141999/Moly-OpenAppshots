# Appshots Context Skill

## 何时使用截图工具

当用户提到以下任一场景时，应主动使用 `take_appshot` 获取屏幕上下文：

- **调试问题**: "帮我看看这个报错"、"这个页面为什么显示不对"
- **UI 分析**: "分析一下这个设计稿"、"这个布局有什么问题"
- **跨应用理解**: 用户正在看浏览器/Terminal/Figma 的内容，需要 AI 理解
- **代码审查**: "帮我 review 这个 PR 页面"
- **文档阅读**: 用户在浏览器中打开文档，希望 AI 参考

## 使用流程

1. 用户提出需要屏幕上下文 → 调用 `take_appshot()`
2. 如果摘要信息（app_name + text_preview）已足够 → 直接回答
3. 如果需要完整内容 → 调用 `get_appshot(snapshot_id, include_image=true)`
4. 如果需要查看历史 → 先用 `list_appshots` 搜索，再 `get_appshot` 获取详情

## 注意事项

- take_appshot 返回的 text_preview 只有前 500 字符，大量文本时需要用 get_appshot
- 发送给 LLM 的截图会自动缩放到 2048px 宽，不会消耗过多 token
- Accessibility Tree 可能很大（3000+ 节点），get_appshot 时根据需要考虑 include_ax_tree=false
